output "role_arns" {
  description = "Map of service name → IRSA role ARN"
  value = {
    for k, role in aws_iam_role.irsa :
    k => role.arn
  }
}

output "role_names" {
  description = "Map of service name → IRSA role name"
  value = {
    for k, role in aws_iam_role.irsa :
    k => role.name
  }
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role — set this as AWS_ROLE_ARN in GitHub secrets"
  value       = aws_iam_role.github_actions.arn
}

output "keda_operator_role_arn" {
  description = "ARN of the KEDA operator IRSA role (annotate the keda-operator service account with this)"
  value       = aws_iam_role.keda_operator.arn
}
