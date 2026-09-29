variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (from eks module output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL of the EKS cluster (with or without https://)"
  type        = string
}

# ── Service Accounts ─────────────────────────
# Map of service-key → { namespace, service_account_name }
# Must include exactly the services that need IRSA roles:
#   auth-service, flag-service, targeting-service,
#   evaluation-service, analytics-service
variable "service_accounts" {
  description = "Map of service name → Kubernetes service account details used to build IRSA trust policies"
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

# ── Resource ARNs (passed from other modules) ─
variable "sqs_queue_arn" {
  description = "ARN of the evaluation_service_queue SQS queue"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the ToggleMasterAnalytics DynamoDB table"
  type        = string
}

variable "region" {
  description = "AWS region (used to build resource ARNs)"
  type        = string
}

# ── GitHub Actions OIDC ──────────────────────
variable "github_org" {
  description = "GitHub organization or username that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}

variable "ecr_repository_names" {
  description = "List of ECR repository names the GitHub Actions role is allowed to push to"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "tfstate_bucket_name" {
  description = "S3 bucket name used for Terraform state (scoped in the deploy policy)"
  type        = string
  default     = "toggle-master-tfstate"
}

variable "tfstate_lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "toggle-master-tfstate-lock"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
