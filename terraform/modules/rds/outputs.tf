output "instance_endpoints" {
  description = "Map of database key → RDS endpoint address"
  value = {
    for k, instance in aws_db_instance.this :
    k => instance.address
  }
}

output "instance_ports" {
  description = "Map of database key → RDS port"
  value = {
    for k, instance in aws_db_instance.this :
    k => instance.port
  }
}

output "instance_arns" {
  description = "Map of database key → RDS instance ARN"
  value = {
    for k, instance in aws_db_instance.this :
    k => instance.arn
  }
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.this.name
}

output "rds_security_group_id" {
  description = "Security group ID attached to the RDS instances"
  value       = aws_security_group.rds.id
}
