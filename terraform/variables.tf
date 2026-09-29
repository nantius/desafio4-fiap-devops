# ═══════════════════════════════════════════════
# Global
# ═══════════════════════════════════════════════
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name — used as a prefix on all resource names"
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ═══════════════════════════════════════════════
# VPC
# ═══════════════════════════════════════════════
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway (cost saving) instead of one per AZ (HA). Set false for production."
  type        = bool
  default     = true
}

# ═══════════════════════════════════════════════
# EKS
# ═══════════════════════════════════════════════
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "toggle"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_group_name" {
  description = "Name suffix for the managed node group"
  type        = string
  default     = "worker-1"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size (GB) per worker node"
  type        = number
  default     = 20
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

# ═══════════════════════════════════════════════
# ECR
# ═══════════════════════════════════════════════
variable "ecr_repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "ecr_max_image_count" {
  description = "Maximum tagged images to retain per ECR repository"
  type        = number
  default     = 10
}

# ═══════════════════════════════════════════════
# RDS
# ═══════════════════════════════════════════════
variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.15"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage_gb" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage_gb" {
  description = "Maximum storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS instances"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection on RDS instances"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set true only for dev/test)"
  type        = bool
  default     = false
}

variable "rds_performance_insights_enabled" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

variable "rds_databases" {
  description = <<-EOT
    Map of RDS instances to create. Each key becomes an identifier suffix.
    Supply passwords via terraform.tfvars or a secrets manager integration —
    never commit plaintext passwords to source control.

    Example:
    rds_databases = {
      "auth-service"      = { db_name = "auth_db",      username = "auth_user",      password = "change-me" }
      "flag-service"      = { db_name = "flag_db",      username = "flag_user",      password = "change-me" }
      "targeting-service" = { db_name = "targeting_db", username = "targeting_user", password = "change-me" }
    }
  EOT
  type = map(object({
    db_name  = string
    username = string
    password = string
  }))
}

# ═══════════════════════════════════════════════
# ElastiCache (Redis)
# ═══════════════════════════════════════════════
variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of Redis nodes (1 = single, >1 = primary + replicas)"
  type        = number
  default     = 1
}

variable "redis_multi_az" {
  description = "Enable Multi-AZ for ElastiCache (only applies when num_cache_clusters > 1)"
  type        = bool
  default     = false
}

variable "redis_snapshot_retention_days" {
  description = "Number of days to retain Redis snapshots"
  type        = number
  default     = 1
}

variable "redis_apply_immediately" {
  description = "Apply ElastiCache changes immediately"
  type        = bool
  default     = false
}

# ═══════════════════════════════════════════════
# DynamoDB
# ═══════════════════════════════════════════════
variable "dynamodb_table_name" {
  description = "DynamoDB table name for analytics events"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery on the DynamoDB table"
  type        = bool
  default     = true
}

variable "dynamodb_enable_user_gsi" {
  description = "Create a GSI on user_id"
  type        = bool
  default     = true
}

variable "dynamodb_enable_flag_gsi" {
  description = "Create a GSI on flag_name"
  type        = bool
  default     = true
}

variable "dynamodb_ttl_attribute" {
  description = "Attribute name for TTL. Leave empty to disable."
  type        = string
  default     = ""
}

# ═══════════════════════════════════════════════
# SQS
# ═══════════════════════════════════════════════
variable "sqs_queue_name" {
  description = "Name of the SQS queue"
  type        = string
  default     = "evaluation_service_queue"
}

variable "sqs_visibility_timeout_seconds" {
  description = "SQS message visibility timeout in seconds"
  type        = number
  default     = 60
}

variable "sqs_message_retention_seconds" {
  description = "How long messages are retained in the queue (seconds)"
  type        = number
  default     = 345600
}

variable "sqs_max_receive_count" {
  description = "Number of receives before a message is sent to the DLQ"
  type        = number
  default     = 5
}

variable "sqs_dlq_message_retention_seconds" {
  description = "How long messages are retained in the DLQ (seconds)"
  type        = number
  default     = 1209600
}

# ═══════════════════════════════════════════════
# GitHub Actions
# ═══════════════════════════════════════════════
variable "github_org" {
  description = "GitHub organization or username that owns the repository (e.g. nantius)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix (e.g. FIAP-devops)"
  type        = string
}

variable "tfstate_bucket_name" {
  description = "S3 bucket name for Terraform state — scoped in the GitHub Actions deploy policy"
  type        = string
  default     = "nantius-toggle-master-tfstate"
}

variable "tfstate_lock_table_name" {
  description = "DynamoDB table name for Terraform state locking — scoped in the deploy policy"
  type        = string
  default     = "toggle-master-tfstate-lock"
}

# ═══════════════════════════════════════════════
# IAM / IRSA service accounts
# ═══════════════════════════════════════════════
variable "service_accounts" {
  description = "Kubernetes service account details per service for IRSA trust policies"
  type = map(object({
    namespace            = string
    service_account_name = string
  }))
  default = {
    "auth-service" = {
      namespace            = "auth-service"
      service_account_name = "auth-service-sa"
    }
    "flag-service" = {
      namespace            = "flag-service"
      service_account_name = "flag-service-sa"
    }
    "targeting-service" = {
      namespace            = "targeting-service"
      service_account_name = "targeting-service-sa"
    }
    "evaluation-service" = {
      namespace            = "evaluation-service"
      service_account_name = "evaluation-service-sa"
    }
    "analytics-service" = {
      namespace            = "analytics-service"
      service_account_name = "analytics-service-sa"
    }
  }
}

# ═══════════════════════════════════════════════
# ArgoCD
# ═══════════════════════════════════════════════
variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD will be installed"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version to install"
  type        = string
  default     = "7.4.4"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitHub repository that holds the GitOps manifests (e.g. https://github.com/org/repo)"
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch ArgoCD watches for changes"
  type        = string
  default     = "main"
}

variable "gitops_manifests_path" {
  description = "Root path inside the repo where per-service manifest folders live"
  type        = string
  default     = "manifests"
}

variable "argocd_services" {
  description = "Map of services ArgoCD will manage. Keys are service names; values provide the target namespace and subfolder path under gitops_manifests_path."
  type = map(object({
    namespace = string
    path      = string
  }))
  default = {
    "auth-service" = {
      namespace = "auth-service"
      path      = "auth-service"
    }
    "flag-service" = {
      namespace = "flag-service"
      path      = "flag-service"
    }
    "targeting-service" = {
      namespace = "targeting-service"
      path      = "targeting-service"
    }
    "evaluation-service" = {
      namespace = "evaluation-service"
      path      = "evaluation-service"
    }
    "analytics-service" = {
      namespace = "analytics-service"
      path      = "analytics-service"
    }
  }
}
