locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# ElastiCache Subnet Group
# Placed in private subnets alongside RDS
# ─────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.project}-${var.environment}-redis-subnet-group"
  description = "Subnet group for ${var.project} ElastiCache Redis"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis-subnet-group"
  })
}

# ─────────────────────────────────────────────
# Security Group — ElastiCache Redis
# Only allows inbound Redis (6379) from the
# EKS worker node security group
# ─────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-redis-sg"
  description = "Allow Redis access from EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  # EKS pods use VPC CNI secondary IPs whose ENI may carry the EKS-managed
  # cluster SG rather than the node SG. Allowing the VPC CIDR ensures pod
  # traffic reaches Redis. Safe because ElastiCache is private (in-VPC only).
  ingress {
    description = "Redis from within the VPC (EKS pods)"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis-sg"
  })
}

# ─────────────────────────────────────────────
# ElastiCache Parameter Group (Redis 7.x)
# ─────────────────────────────────────────────
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project}-${var.environment}-redis7"
  family = "redis7"

  # Enable keyspace notifications for expired/evicted events (useful for pub/sub patterns)
  parameter {
    name  = "notify-keyspace-events"
    value = ""
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# ElastiCache Replication Group (Redis)
# Used exclusively by evaluation-service as a
# session/feature-flag evaluation cache.
#
# Single-node by default (num_cache_clusters=1).
# Set var.num_cache_clusters > 1 for read replicas.
# ─────────────────────────────────────────────
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-${var.environment}-redis"
  description          = "Redis cache for ${var.project} evaluation-service"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  engine               = "redis"
  engine_version       = var.engine_version

  # Encryption in-transit and at-rest
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  # transit_encryption_mode must be "required" when transit_encryption_enabled is true
  transit_encryption_mode    = "required"

  automatic_failover_enabled = var.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = var.num_cache_clusters > 1 ? var.multi_az : false

  snapshot_retention_limit = var.snapshot_retention_days
  snapshot_window          = "02:00-03:00"
  maintenance_window       = "sun:03:00-sun:04:00"

  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-redis"
    Service = "evaluation-service"
  })
}
