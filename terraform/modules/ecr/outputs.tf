output "repository_urls" {
  description = "Map of repository name → repository URL"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository name → repository ARN"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.arn
  }
}

output "registry_id" {
  description = "Registry ID (AWS account ID) shared by all repositories"
  value       = length(aws_ecr_repository.this) > 0 ? values(aws_ecr_repository.this)[0].registry_id : ""
}
