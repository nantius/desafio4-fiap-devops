output "primary_endpoint" {
  description = "Primary endpoint address for Redis (use for read/write)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address for Redis (use for read-only when replicas exist)"
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.this.port
}

output "replication_group_id" {
  description = "ElastiCache replication group ID"
  value       = aws_elasticache_replication_group.this.id
}

output "security_group_id" {
  description = "Security group ID attached to the ElastiCache cluster"
  value       = aws_security_group.redis.id
}

output "connection_url" {
  description = "Redis connection URL (rediss:// — TLS required)"
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:${aws_elasticache_replication_group.this.port}"
}
