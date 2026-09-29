# ═══════════════════════════════════════════════
# VPC
# ═══════════════════════════════════════════════
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# ═══════════════════════════════════════════════
# EKS
# ═══════════════════════════════════════════════
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN (used for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes"
  value       = module.eks.node_security_group_id
}

# ═══════════════════════════════════════════════
# ECR
# ═══════════════════════════════════════════════
output "ecr_repository_urls" {
  description = "Map of service name → ECR repository URL"
  value       = module.ecr.repository_urls
}

# ═══════════════════════════════════════════════
# RDS
# ═══════════════════════════════════════════════
output "rds_endpoints" {
  description = "Map of database key → RDS endpoint address"
  value       = module.rds.instance_endpoints
}

output "rds_security_group_id" {
  description = "Security group ID attached to RDS instances"
  value       = module.rds.rds_security_group_id
}

# ═══════════════════════════════════════════════
# ElastiCache
# ═══════════════════════════════════════════════
output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = module.elasticache.primary_endpoint
}

output "redis_connection_url" {
  description = "Redis connection URL (rediss:// — TLS required)"
  value       = module.elasticache.connection_url
}

# ═══════════════════════════════════════════════
# DynamoDB
# ═══════════════════════════════════════════════
output "dynamodb_table_name" {
  description = "DynamoDB analytics table name"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "DynamoDB analytics table ARN"
  value       = module.dynamodb.table_arn
}

# ═══════════════════════════════════════════════
# SQS
# ═══════════════════════════════════════════════
output "sqs_queue_url" {
  description = "URL of the evaluation_service_queue (set as AWS_SQS_URL in services)"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN of the evaluation_service_queue"
  value       = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  description = "URL of the Dead-Letter Queue"
  value       = module.sqs.dlq_url
}

# ═══════════════════════════════════════════════
# IAM / IRSA
# ═══════════════════════════════════════════════
output "irsa_role_arns" {
  description = "Map of service name → IRSA role ARN (use in K8s ServiceAccount annotations)"
  value       = module.iam.role_arns
}

output "github_actions_role_arn" {
  description = "ARN to set as AWS_ROLE_ARN in GitHub repository secrets"
  value       = module.iam.github_actions_role_arn
}

# ═══════════════════════════════════════════════
# ArgoCD
# ═══════════════════════════════════════════════
output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = module.argocd.argocd_namespace
}

output "argocd_chart_version" {
  description = "Installed ArgoCD Helm chart version"
  value       = module.argocd.argocd_chart_version
}

output "argocd_server_service_name" {
  description = "K8s service name for the ArgoCD API server — use with: kubectl port-forward svc/<value> -n argocd 8080:443"
  value       = module.argocd.argocd_server_service_name
}

output "argocd_application_names" {
  description = "ArgoCD Application names created for each service"
  value       = module.argocd.argocd_application_names
}
