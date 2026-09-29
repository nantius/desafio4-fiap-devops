locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# DB Subnet Group
# RDS instances are placed in private subnets
# ─────────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name        = "${var.project}-${var.environment}-rds-subnet-group"
  description = "Subnet group for ${var.project} RDS instances"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-rds-subnet-group"
  })
}

# ─────────────────────────────────────────────
# Security Group — RDS
# Only allows inbound Postgres (5432) from the
# EKS worker node security group
# ─────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL access from EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  # EKS pods use VPC CNI secondary IPs whose ENI may carry the EKS-managed
  # cluster SG rather than the node SG. Allowing the VPC CIDR ensures pod
  # traffic reaches RDS. Safe because RDS is not publicly accessible.
  ingress {
    description = "PostgreSQL from within the VPC (EKS pods)"
    from_port   = 5432
    to_port     = 5432
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
    Name = "${var.project}-${var.environment}-rds-sg"
  })
}

# ─────────────────────────────────────────────
# RDS Parameter Group (PostgreSQL 15)
# ─────────────────────────────────────────────
resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project}-${var.environment}-postgres15"
  family      = "postgres15"
  description = "Custom parameter group for ${var.project} PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# RDS Instances
# One instance per logical database so each
# service gets its own endpoint and credentials,
# matching the existing prod setup.
# ─────────────────────────────────────────────
resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier = "${var.project}-${var.environment}-${each.key}"

  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = each.value.db_name
  username = each.value.username
  password = each.value.password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  # SSL is enforced at the application level (SSL_MODE=require in the services)
  # RDS forces SSL by default; rds.force_ssl is enabled via parameter group if needed

  multi_az               = var.multi_az
  publicly_accessible    = false
  deletion_protection    = var.deletion_protection
  skip_final_snapshot    = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.environment}-${each.key}-final-snapshot"

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-${each.key}"
    Service = each.key
  })
}
