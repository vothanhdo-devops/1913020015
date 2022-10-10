provider "aws" {
  region = var.region
}
# Create VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block           = var.custom_vpc
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
}
# Create Public Subnet for EC2
data "aws_availability_zones" "azs" {}
resource "aws_subnet" "public_subnet" {
  count             = var.custom_vpc == "10.0.0.0/16" ? 3 : 0
  vpc_id            = aws_vpc.custom_vpc.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = element(cidrsubnets(var.custom_vpc, 8, 4, 4), count.index)

  tags = {
    "Name" = "Public-Subnet-${count.index}"
  }
}
# Create Private subnet for RDS
resource "aws_subnet" "subnet-private-1" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = var.AZ3
}
# Create second Private subnet for RDS
resource "aws_subnet" "subnet-private-2" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = var.AZ4
}
# Create IGW for internet connection 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = {
    "Name" = "Internet-Gateway-webserver"
  }
}
# Creating Route table 
resource "aws_route_table" "public_crt" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
# Associating route tabe to public subnet
resource "aws_route_table_association" "public_rt_association" {
  count          = length(aws_subnet.public_subnet) == 3 ? 3 : 0
  route_table_id = aws_route_table.public_crt.id
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
}
## Security Group for ELB
resource "aws_security_group" "elb" {
  vpc_id = aws_vpc.custom_vpc.id
  name = "terraform-webserver-elb"
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "MYSQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "EFS mount target"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
    tags = {
    Name = "allow http,ssh,db"
  }
}
# Security group for RDS
resource "aws_security_group" "RDS_allow_rule" {
  vpc_id = aws_vpc.custom_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ec2"
  }
}
# Create RDS Subnet group
resource "aws_db_subnet_group" "RDS_subnet_grp" {
  subnet_ids = ["${aws_subnet.subnet-private-1.id}", "${aws_subnet.subnet-private-2.id}"]
}
# Create RDS instance
resource "aws_db_instance" "wordpressdb" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.instance_class
  db_subnet_group_name   = aws_db_subnet_group.RDS_subnet_grp.id
  vpc_security_group_ids = ["${aws_security_group.RDS_allow_rule.id}"]
  db_name                = var.database_name
  username               = var.database_user
  password               = var.database_password
  skip_final_snapshot    = true
}
# change USERDATA varible
data "template_file" "playbook_db" {
  template = file("../ansible/roles/copy/tasks/default.yml")
  vars = {
    db_username      = "${var.database_user}"
    db_user_password = "${var.database_password}"
    db_name          = "${var.database_name}"
    db_RDS           = "${aws_db_instance.wordpressdb.endpoint}"
    my_domain        = "http://${aws_elb.webserver-elb.dns_name} "
  }
}
data "template_file" "playbook_efs" {
  template = file("../ansible/roles/mount_efs/tasks/default.yml")
  vars = {
    aws_efs_dns = "${aws_efs_file_system.efs.dns_name}"
  }
}
# Read ami id just created.
data "aws_ami" "ecs_optimized" {
  most_recent = true
  filter {
    name   = "name"
    values = ["aws-linux-website-wordpess"]
  }
}
# Save Rendered playbook content to local file
resource "local_file" "playbook-rendered-file" {
  content   = "${data.template_file.playbook_db.rendered}"
  filename  = "../ansible/roles/copy/tasks/main.yml"
}
resource "local_file" "playbook-rendered-file-2" {
  content   = "${data.template_file.playbook_efs.rendered}"
  filename  = "../ansible/roles/mount_efs/tasks/main.yml"
}
# Create EC2 ( only after RDS is provisioned)
resource "aws_instance" "wordpress" {
  count           = length(aws_subnet.public_subnet.*.id)
  ami             = data.aws_ami.ecs_optimized.id
  instance_type   = var.instance_type
  monitoring      = true
  subnet_id       = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = ["${aws_security_group.elb.id}"]
  key_name        = aws_key_pair.mykey-pair.id
  tags = {
    "Name"        = "Instance-${count.index}"
    "Environment" = "Test"
    "CreatedBy"   = "Terraform"
  }
  timeouts {
    create = "10m"
  }
}
resource "aws_key_pair" "mykey-pair" {
  key_name   = "vothanhdo"
  public_key = file(var.PUBLIC_KEY_PATH)
}
# creating Elastic IP for EC2
resource "aws_eip" "eip" {
  count            = length(aws_instance.wordpress.*.id)
  instance         = element(aws_instance.wordpress.*.id, count.index)
  public_ipv4_pool = "amazon"
  vpc              = true
  tags = {
    "Name" = "EIP-${count.index}"
  }
}
# Creating EIP association with EC2 Instances:
resource "aws_eip_association" "eip_association" {
  count         = length(aws_eip.eip)
  instance_id   = element(aws_instance.wordpress.*.id, count.index)
  allocation_id = element(aws_eip.eip.*.id, count.index)
}
# Creating EFS file system
resource "aws_efs_file_system" "efs" {
  creation_token = "my-efs-webserver"
  tags   = {
    Name = "Webserver"
  }
}
# Creating Mount target of EFS
resource "aws_efs_mount_target" "mount" {
  count           = length(aws_subnet.public_subnet.*.id)
  file_system_id  = element(aws_efs_file_system.efs.*.id, count.index)
  subnet_id       = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.elb.id]
}
# Remote
resource "null_resource" "Wordpress_config_1" {
  count         = length(aws_subnet.public_subnet.*.id)
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.PRIV_KEY_PATH)
    host        = element(aws_eip.eip.*.public_ip, count.index)
  }
# Run script to update python on remote client
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install python3 -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo yum install nfs-utils -y -q",
    ]
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ec2-user -i '${element(aws_eip.eip.*.public_ip, count.index)},' --private-key ${var.PRIV_KEY_PATH}  '../ansible/playbook-2.yml'"
  }
  depends_on = [aws_db_instance.wordpressdb, aws_efs_file_system.efs]
}
resource "time_sleep" "wait_60_seconds" {
  depends_on = [null_resource.Wordpress_config_1]
  create_duration = "60s"
}
# Remote 2
resource "null_resource" "Wordpress_config_2" {
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.PRIV_KEY_PATH)
    host        = aws_eip.eip[0].public_ip
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ec2-user -i '${aws_eip.eip[0].public_ip},' --private-key ${var.PRIV_KEY_PATH}  '../ansible/playbook-3.yml'"
  }
  depends_on = [null_resource.Wordpress_config_1]
}
resource "time_sleep" "wait_15_seconds" {
  depends_on = [null_resource.Wordpress_config_2]
  create_duration = "15s"
}
# Target Group Creation
resource "aws_lb_target_group" "target_group_webserver" {
  name        = "TargetGroup"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.custom_vpc.id
}
# Target Group Attachment with Instance
resource "aws_alb_target_group_attachment" "target_group_webserver_attachment" {
  count            = length(aws_instance.wordpress.*.id) == 3 ? 3 : 0
  target_group_arn = aws_lb_target_group.target_group_webserver.arn
  target_id        = element(aws_instance.wordpress.*.id, count.index)
}
### Creating ELB
resource "aws_elb" "webserver-elb" {
  name                  = "terraform-elb-webserver"
  security_groups       = ["${aws_security_group.elb.id}"]
  subnets               = aws_subnet.public_subnet.*.id
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:80/"
  }
  listener {
    lb_port             = 80
    lb_protocol         = "http"
    instance_port       = "80"
    instance_protocol   = "http"
  }
  instances           = aws_instance.wordpress.*.id
}