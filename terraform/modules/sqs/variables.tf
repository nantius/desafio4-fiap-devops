variable "project" {
  description = "Project name used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
  default     = "evaluation_service_queue"
}

# ── Queue settings ───────────────────────────
variable "visibility_timeout_seconds" {
  description = "Visibility timeout for messages (should be > max processing time)"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long messages are retained in the queue (seconds). Default: 4 days."
  type        = number
  default     = 345600
}

variable "max_message_size_bytes" {
  description = "Maximum message size in bytes (max 262144 = 256 KB)"
  type        = number
  default     = 262144
}

# ── DLQ ─────────────────────────────────────
variable "max_receive_count" {
  description = "Number of times a message can be received before being moved to the DLQ"
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "How long messages are retained in the DLQ (seconds). Default: 14 days."
  type        = number
  default     = 1209600
}

# ── Access control ───────────────────────────
variable "producer_role_arns" {
  description = "List of IAM role ARNs allowed to send messages (evaluation-service)"
  type        = list(string)
  default     = []
}

variable "consumer_role_arns" {
  description = "List of IAM role ARNs allowed to receive/delete messages (analytics-service, KEDA)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
