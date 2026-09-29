output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_chart_version" {
  description = "Installed ArgoCD Helm chart version"
  value       = helm_release.argocd.version
}

output "argocd_server_service_name" {
  description = "Kubernetes service name for the ArgoCD API server (use with kubectl port-forward)"
  value       = "argocd-server"
}

output "argocd_application_names" {
  description = "List of ArgoCD Application names created by this module"
  value       = keys(var.services)
}

output "metrics_server_chart_version" {
  description = "Installed metrics-server Helm chart version"
  value       = helm_release.metrics_server.version
}

output "nginx_ingress_chart_version" {
  description = "Installed ingress-nginx Helm chart version"
  value       = helm_release.nginx_ingress.version
}

output "keda_chart_version" {
  description = "Installed KEDA Helm chart version"
  value       = helm_release.keda.version
}
