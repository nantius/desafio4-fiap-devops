variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where ElastiCache will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes (granted inbound access on port 6379)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — allowed inbound on 6379 so EKS pods (VPC CNI IPs) can reach Redis regardless of which SG their ENI carries"
  type        = string
}

# ── Engine ───────────────────────────────────
variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

# ── Cluster ──────────────────────────────────
variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes). 1 = single node, >1 = primary + replicas"
  type        = number
  default     = 1
}

variable "multi_az" {
  description = "Enable Multi-AZ for the replication group. Only applies when num_cache_clusters > 1."
  type        = bool
  default     = false
}

# ── Maintenance ──────────────────────────────
variable "snapshot_retention_days" {
  description = "Number of days to retain Redis snapshots (0 disables snapshots)"
  type        = number
  default     = 1
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of during the next maintenance window"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
