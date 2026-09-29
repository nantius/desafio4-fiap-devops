variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where RDS will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes (granted inbound access on port 5432)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — allowed inbound on 5432 so EKS pods (which use VPC CNI IPs) can reach RDS regardless of which SG their ENI carries"
  type        = string
}

# ── Engine ───────────────────────────────────
variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.15"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage for autoscaling in GB. Set to 0 to disable autoscaling."
  type        = number
  default     = 100
}

# ── Databases ────────────────────────────────
# Each entry in this map provisions one RDS instance.
# key        — used in the resource identifier and tags
# db_name    — logical database name inside the instance
# username   — master username
# password   — master password (use Secrets Manager or tfvars, never hardcode)
variable "databases" {
  description = "Map of RDS instances to create. Key is used as an identifier suffix."
  type = map(object({
    db_name  = string
    username = string
    password = string
  }))
}

# ── HA / Maintenance ─────────────────────────
variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection on RDS instances"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying an instance (set true only for dev/test)"
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
