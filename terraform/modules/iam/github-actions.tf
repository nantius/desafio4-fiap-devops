# ─────────────────────────────────────────────
# GitHub Actions — OIDC Role
#
# A single role assumed by GitHub Actions via
# OIDC for two purposes:
#   1. ECR push (all five service repositories)
#   2. Terraform plan/apply (infra management)
#
# The trust is scoped to a specific GitHub repo
# so no other repository can assume this role.
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────
# GitHub Actions OIDC Provider
#
# Registers GitHub's OIDC issuer with AWS IAM so
# workflows can exchange their OIDC token for AWS
# credentials via AssumeRoleWithWebIdentity.
# Only one of these may exist per account, so it
# is created here (idempotent for this account).
# ─────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint is no longer validated by AWS for this
  # well-known IdP, but the field is still required by the API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-github-actions-oidc"
  })
}

# ── Trust Policy ─────────────────────────────
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be sts.amazonaws.com
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to a specific GitHub repo — any branch or tag.
    # The org has a customized OIDC subject claim template that injects
    # immutable numeric IDs (e.g. repo:nantius@9022731/repo@1354099251:...),
    # so we match with wildcards around the org and repo segments.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:*",
        "repo:${var.github_org}@*/${var.github_repo}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-${var.environment}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-github-actions-role"
    Purpose = "github-actions-cicd"
  })
}

# ── Policy 1: ECR Push ───────────────────────
data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken is account-level — cannot be scoped to a resource
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    # Scoped to the five project repositories only
    resources = [
      for repo in var.ecr_repository_names :
      "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${repo}"
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name   = "ecr-push-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ── Policy 2: Terraform Infra Management ─────
data "aws_iam_policy_document" "terraform_deploy" {
  # ── Networking (VPC, subnets, IGW, NAT, SGs, route tables) ──
  statement {
    sid       = "EC2Networking"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  # ── EKS ─────────────────────────────────────
  statement {
    sid       = "EKS"
    effect    = "Allow"
    actions   = ["eks:*"]
    resources = ["*"]
  }

  # ── RDS ─────────────────────────────────────
  statement {
    sid       = "RDS"
    effect    = "Allow"
    actions   = ["rds:*"]
    resources = ["*"]
  }

  # ── ElastiCache ──────────────────────────────
  statement {
    sid       = "ElastiCache"
    effect    = "Allow"
    actions   = ["elasticache:*"]
    resources = ["*"]
  }

  # ── DynamoDB ─────────────────────────────────
  statement {
    sid       = "DynamoDB"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = ["*"]
  }

  # ── SQS ──────────────────────────────────────
  statement {
    sid       = "SQS"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = ["*"]
  }

  # ── S3 (Terraform state bucket only) ─────────
  statement {
    sid    = "S3TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket_name}",
      "arn:aws:s3:::${var.tfstate_bucket_name}/*",
    ]
  }

  # ── DynamoDB lock table (Terraform state locking) ──
  statement {
    sid    = "DynamoDBTerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.tfstate_lock_table_name}",
    ]
  }

  # ── IAM (needed to manage IRSA roles + OIDC provider) ──
  statement {
    sid    = "IAMManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # ── CloudWatch Logs (EKS control plane logging) ──
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagLogGroup",
      "logs:ListTagsLogGroup",
    ]
    resources = ["*"]
  }

  # ── KMS (SQS + ElastiCache + RDS encryption) ─
  statement {
    sid    = "KMSDescribe"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:ListAliases",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  name   = "terraform-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.terraform_deploy.json
}
