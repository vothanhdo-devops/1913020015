output "public_ip" {
  value = zipmap(aws_instance.wordpress.*.tags.Name, aws_eip.eip.*.public_ip)
}
output "INFO-ELB-DNS" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://${aws_elb.webserver-elb.dns_name} "
}