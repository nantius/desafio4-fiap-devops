variable "project" {
  description = "Project name — used as a prefix on resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "region" {
  description = "AWS region — used to configure kubeconfig for kubectl calls"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used by the Kubernetes / Helm providers)"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  type        = string
  sensitive   = true
}

variable "keda_chart_version" {
  description = "KEDA Helm chart version to install"
  type        = string
  default     = "2.15.1"
}

variable "keda_operator_role_arn" {
  description = "IRSA role ARN to annotate on the keda-operator service account (for SQS scaler auth)"
  type        = string
}

variable "nginx_ingress_chart_version" {
  description = "ingress-nginx Helm chart version to install"
  type        = string
  default     = "4.10.1"
}

variable "metrics_server_chart_version" {
  description = "metrics-server Helm chart version to install"
  type        = string
  default     = "3.12.2"
}

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
  description = "HTTPS URL of the GitHub repository that holds the GitOps manifests"
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch ArgoCD watches for changes in the GitOps repo"
  type        = string
  default     = "main"
}

variable "gitops_manifests_path" {
  description = "Root path inside the repo where per-service manifest folders live (e.g. manifests)"
  type        = string
  default     = "manifests"
}

variable "services" {
  description = <<-EOT
    Map of service definitions. Each key is the service name; the value
    contains the Kubernetes namespace and the relative path (under
    gitops_manifests_path) for that service's manifests.
  EOT
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

variable "tags" {
  description = "Additional tags (applied to any AWS-side resources created by this module)"
  type        = map(string)
  default     = {}
}
