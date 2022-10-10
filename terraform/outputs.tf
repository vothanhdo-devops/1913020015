output "RDS-Endpoint" {
  value = aws_db_instance.wordpressdb.endpoint
}
output "alb_id" {
  value = aws_lb.lb.dns_name
}
output "public_ip" {
  value = zipmap(aws_instance.wordpress.*.tags.Name, aws_eip.eip.*.public_ip)
}
output "INFO-ELB-DNS" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://${aws_lb.lb.dns_name} "
}