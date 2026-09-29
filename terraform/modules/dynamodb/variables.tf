variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery (PITR)"
  type        = bool
  default     = true
}

variable "ttl_attribute" {
  description = "Attribute name to use as TTL. Leave empty to disable TTL."
  type        = string
  default     = ""
}

variable "enable_user_gsi" {
  description = "Create a Global Secondary Index on user_id for per-user queries"
  type        = bool
  default     = true
}

variable "enable_flag_gsi" {
  description = "Create a Global Secondary Index on flag_name for per-flag queries"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
