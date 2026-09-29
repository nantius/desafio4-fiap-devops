terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  backend "s3" {
    bucket         = "nantius-toggle-master-tfstate"
    key            = "desafio3/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "toggle-master-tfstate-lock"
    use_lockfile   = true
  }
}
