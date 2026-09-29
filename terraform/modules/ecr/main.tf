locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# ECR Repositories
# One repository per service. All are private.
# ─────────────────────────────────────────────
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.key
  image_tag_mutability = var.image_tag_mutability

  # Allow `terraform destroy` to delete the repository even when it still
  # contains images (otherwise ECR returns RepositoryNotEmptyException).
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = each.key
  })
}

# ─────────────────────────────────────────────
# Lifecycle Policy
# Keeps the last N tagged images and purges
# untagged images older than 1 day to control
# storage costs.
# ─────────────────────────────────────────────
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "prod", "staging", "sha"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# Repository Policy
# Grants EKS node role pull access to all repos.
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid    = "AllowEKSNodePull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.pull_role_arns
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = length(var.pull_role_arns) > 0 ? aws_ecr_repository.this : {}
  repository = each.value.name
  policy     = data.aws_iam_policy_document.ecr_pull.json
}
