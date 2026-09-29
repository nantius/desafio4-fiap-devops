terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name   = var.argocd_namespace
    labels = local.common_tags
  }
}

# ─────────────────────────────────────────────
# KEDA — Kubernetes Event-driven Autoscaling
# Used by analytics-service to scale based on
# SQS queue depth (ScaledObject + TriggerAuthentication).
# Must be installed before ArgoCD syncs analytics-service.
# ─────────────────────────────────────────────
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_chart_version
  namespace  = "keda"

  create_namespace = true
  wait             = true
  timeout          = 300

  # Annotate the keda-operator service account with the IRSA role so the
  # operator can assume AWS credentials (used by the SQS scaler for
  # analytics-service via TriggerAuthentication identityOwner: operator).
  set {
    name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.keda_operator_role_arn
  }

  depends_on = [kubernetes_namespace.argocd]
}

# ─────────────────────────────────────────────
# NGINX Ingress Controller
# Creates a single AWS NLB (LoadBalancer Service)
# shared by all 5 services via path-based routing.
# ─────────────────────────────────────────────
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.nginx_ingress_chart_version
  namespace  = "ingress-nginx"

  create_namespace = true
  wait             = true
  timeout          = 300

  # Use AWS NLB instead of the classic ELB
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  # Expose controller metrics for Prometheus scraping
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# ─────────────────────────────────────────────
# Metrics Server
# Required for: kubectl top, HPA, cluster autoscaler
# EKS does not ship this by default.
# ─────────────────────────────────────────────
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  wait    = true
  timeout = 300

  # Required on EKS: the kubelet serving cert is self-signed,
  # so the metrics-server must skip TLS verification for kubelet scrapes.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# ─────────────────────────────────────────────
# ArgoCD — installed via official Helm chart
# ─────────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Keep CRDs up-to-date when upgrading the chart
  skip_crds = false

  # Wait until all pods are Ready before Terraform marks this as done
  wait    = true
  timeout = 600

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Expose server metrics for Prometheus scraping
  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  # Disable the default admin password so we manage access via SSO / tokens
  # (remove this block if you want an auto-generated admin password)
  set {
    name  = "configs.params.server\\.insecure"
    value = "false"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# ─────────────────────────────────────────────
# ArgoCD Applications — one per service
#
# kubernetes_manifest validates against the live
# cluster API at plan time, so it fails before
# the ArgoCD CRDs exist. We use kubectl via
# null_resource + local-exec instead, which runs
# only after helm_release.argocd completes.
# ─────────────────────────────────────────────
resource "null_resource" "argocd_apps" {
  # Re-run whenever the set of services or repo config changes
  triggers = {
    services      = jsonencode(var.services)
    repo_url      = var.gitops_repo_url
    repo_branch   = var.gitops_repo_branch
    manifests_path = var.gitops_manifests_path
    cluster_name  = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --kubeconfig /tmp/kubeconfig-argocd
      %{for name, svc in var.services}
      kubectl apply --kubeconfig /tmp/kubeconfig-argocd -f - <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${name}
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: ${var.gitops_repo_branch}
    path: ${var.gitops_manifests_path}/${svc.path}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${svc.namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
YAML
      %{endfor}
    EOT
  }

  depends_on = [helm_release.argocd]
}
