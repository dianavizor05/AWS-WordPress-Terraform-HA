output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. Open this address in browser."
  value       = aws_lb.wordpress.dns_name
}

output "wordpress_url" {
  description = "WordPress URL."
  value       = "http://${aws_lb.wordpress.dns_name}"
}

output "vpc_id" {
  description = "Created VPC ID."
  value       = aws_vpc.main.id
}

output "bastion_public_ips" {
  description = "Public IP addresses of bastion hosts."
  value       = aws_instance.bastion[*].public_ip
}

output "rds_endpoint" {
  description = "Private RDS endpoint."
  value       = aws_db_instance.wordpress.address
}

output "efs_id" {
  description = "EFS file system ID."
  value       = aws_efs_file_system.wordpress.id
}