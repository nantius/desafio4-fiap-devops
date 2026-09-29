provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ─────────────────────────────────────────────
# Helm & Kubernetes providers
# Both are configured after EKS is created so
# they can authenticate against the cluster.
# ─────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", var.cluster_name,
        "--region", var.region,
      ]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.region,
    ]
  }
}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  environment          = var.environment
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = var.tags
}

# ─────────────────────────────────────────────
# EKS
# ─────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project             = var.project
  environment         = var.environment
  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids

  node_group_name     = var.node_group_name
  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_disk_size_gb   = var.node_disk_size_gb
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  tags                = var.tags
}

# ─────────────────────────────────────────────
# ECR  (no VPC dependency — create early so
# images can be pushed before cluster is ready)
# ─────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project          = var.project
  environment      = var.environment
  repository_names = var.ecr_repository_names
  max_image_count  = var.ecr_max_image_count

  # Grant the EKS node role pull access
  pull_role_arns = [module.eks.node_role_arn]
  tags           = var.tags
}

# ─────────────────────────────────────────────
# RDS  (PostgreSQL — auth_db, flag_db, targeting_db)
# ─────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  vpc_cidr                   = var.vpc_cidr

  engine_version               = var.rds_engine_version
  instance_class               = var.rds_instance_class
  allocated_storage_gb         = var.rds_allocated_storage_gb
  max_allocated_storage_gb     = var.rds_max_allocated_storage_gb
  multi_az                     = var.rds_multi_az
  backup_retention_days        = var.rds_backup_retention_days
  deletion_protection          = var.rds_deletion_protection
  skip_final_snapshot          = var.rds_skip_final_snapshot
  performance_insights_enabled = var.rds_performance_insights_enabled

  # Sensitive — supply via terraform.tfvars or environment-specific secrets
  databases = var.rds_databases
  tags      = var.tags
}

# ─────────────────────────────────────────────
# ElastiCache  (Redis — evaluation-service)
# ─────────────────────────────────────────────
module "elasticache" {
  source = "./modules/elasticache"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  vpc_cidr                   = var.vpc_cidr

  engine_version          = var.redis_engine_version
  node_type               = var.redis_node_type
  num_cache_clusters      = var.redis_num_cache_clusters
  multi_az                = var.redis_multi_az
  snapshot_retention_days = var.redis_snapshot_retention_days
  apply_immediately       = var.redis_apply_immediately
  tags                    = var.tags
}

# ─────────────────────────────────────────────
# DynamoDB  (ToggleMasterAnalytics)
# ─────────────────────────────────────────────
module "dynamodb" {
  source = "./modules/dynamodb"

  project                = var.project
  environment            = var.environment
  table_name             = var.dynamodb_table_name
  billing_mode           = var.dynamodb_billing_mode
  point_in_time_recovery = var.dynamodb_point_in_time_recovery
  enable_user_gsi        = var.dynamodb_enable_user_gsi
  enable_flag_gsi        = var.dynamodb_enable_flag_gsi
  ttl_attribute          = var.dynamodb_ttl_attribute
  tags                   = var.tags
}

# ─────────────────────────────────────────────
# SQS  (evaluation_service_queue)
# ─────────────────────────────────────────────
module "sqs" {
  source = "./modules/sqs"

  project     = var.project
  environment = var.environment
  queue_name  = var.sqs_queue_name

  visibility_timeout_seconds    = var.sqs_visibility_timeout_seconds
  message_retention_seconds     = var.sqs_message_retention_seconds
  max_receive_count             = var.sqs_max_receive_count
  dlq_message_retention_seconds = var.sqs_dlq_message_retention_seconds

  # Wire IRSA role ARNs after IAM module runs
  producer_role_arns = [module.iam.role_arns["evaluation-service"]]
  consumer_role_arns = [module.iam.role_arns["analytics-service"]]
  tags               = var.tags
}

# ─────────────────────────────────────────────
# IAM / IRSA  (one role per service)
# Depends on EKS (OIDC), SQS, and DynamoDB
# ─────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  project           = var.project
  environment       = var.environment
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  service_accounts  = var.service_accounts
  sqs_queue_arn     = module.sqs.queue_arn
  dynamodb_table_arn = module.dynamodb.table_arn

  github_org              = var.github_org
  github_repo             = var.github_repo
  ecr_repository_names    = var.ecr_repository_names
  tfstate_bucket_name     = var.tfstate_bucket_name
  tfstate_lock_table_name = var.tfstate_lock_table_name
  tags                    = var.tags
}

# ─────────────────────────────────────────────
# ArgoCD  (Helm install + Application CRs)
# Must run after EKS so Helm/K8s providers work.
# ─────────────────────────────────────────────
module "argocd" {
  source = "./modules/argocd"

  project      = var.project
  environment  = var.environment
  cluster_name = var.cluster_name

  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = module.eks.cluster_ca_certificate
  region                 = var.region

  argocd_namespace     = var.argocd_namespace
  argocd_chart_version = var.argocd_chart_version

  keda_operator_role_arn = module.iam.keda_operator_role_arn

  gitops_repo_url       = var.gitops_repo_url
  gitops_repo_branch    = var.gitops_repo_branch
  gitops_manifests_path = var.gitops_manifests_path

  services = var.argocd_services
  tags     = var.tags
}
