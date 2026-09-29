variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create (one per service)"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "image_tag_mutability" {
  description = "Tag mutability for repositories: MUTABLE or IMMUTABLE"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain per repository"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images"
  type        = bool
  default     = true
}

variable "pull_role_arns" {
  description = "List of IAM role ARNs that are allowed to pull images (e.g. EKS node role)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
