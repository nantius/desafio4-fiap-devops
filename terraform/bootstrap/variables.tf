variable "region" {
  description = "AWS region for the bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket used to store Terraform state"
  type        = string
  default     = "nantius-toggle-master-tfstate"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "toggle-master-tfstate-lock"
}
