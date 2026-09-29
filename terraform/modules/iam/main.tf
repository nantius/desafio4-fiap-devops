locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # Strip the "https://" prefix once — reused in every trust policy condition
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

# ─────────────────────────────────────────────
# Helper: reusable IRSA trust policy document
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "irsa_trust" {
  for_each = var.service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ─────────────────────────────────────────────
# IRSA Roles — one per service
# ─────────────────────────────────────────────
resource "aws_iam_role" "irsa" {
  for_each = var.service_accounts

  name               = "${var.project}-${var.environment}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-${each.key}-role"
    Service = each.key
  })
}

# ═══════════════════════════════════════════════
# Per-service IAM policies
# ═══════════════════════════════════════════════

# ─────────────────────────────────────────────
# auth-service
# Needs: (none beyond VPC/RDS — accessed via
# network, no AWS API calls from the app itself)
# We still create the role so the K8s
# service account annotation is consistent.
# ─────────────────────────────────────────────
resource "aws_iam_role_policy" "auth_service" {
  name = "${var.project}-${var.environment}-auth-service-policy"
  role = aws_iam_role.irsa["auth-service"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowDescribeSelf"
      Effect   = "Allow"
      Action   = ["sts:GetCallerIdentity"]
      Resource = "*"
    }]
  })
}

# ─────────────────────────────────────────────
# flag-service
# Needs: (none beyond VPC/RDS — same rationale)
# ─────────────────────────────────────────────
resource "aws_iam_role_policy" "flag_service" {
  name = "${var.project}-${var.environment}-flag-service-policy"
  role = aws_iam_role.irsa["flag-service"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowDescribeSelf"
      Effect   = "Allow"
      Action   = ["sts:GetCallerIdentity"]
      Resource = "*"
    }]
  })
}

# ─────────────────────────────────────────────
# targeting-service
# Needs: (none beyond VPC/RDS — same rationale)
# ─────────────────────────────────────────────
resource "aws_iam_role_policy" "targeting_service" {
  name = "${var.project}-${var.environment}-targeting-service-policy"
  role = aws_iam_role.irsa["targeting-service"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowDescribeSelf"
      Effect   = "Allow"
      Action   = ["sts:GetCallerIdentity"]
      Resource = "*"
    }]
  })
}

# ─────────────────────────────────────────────
# evaluation-service
# Needs:
#   SQS  — SendMessage on evaluation_service_queue
#   ElastiCache — network only (no IAM actions)
# ─────────────────────────────────────────────
resource "aws_iam_role_policy" "evaluation_service" {
  name = "${var.project}-${var.environment}-evaluation-service-policy"
  role = aws_iam_role.irsa["evaluation-service"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSendMessage"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
        ]
        Resource = [var.sqs_queue_arn]
      }
    ]
  })
}

# ─────────────────────────────────────────────
# analytics-service
# Needs:
#   SQS      — ReceiveMessage, DeleteMessage,
#              ChangeMessageVisibility,
#              GetQueueAttributes (also used by KEDA)
#   DynamoDB — PutItem on ToggleMasterAnalytics
# ─────────────────────────────────────────────
resource "aws_iam_role_policy" "analytics_service" {
  name = "${var.project}-${var.environment}-analytics-service-policy"
  role = aws_iam_role.irsa["analytics-service"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = [var.sqs_queue_arn]
      },
      {
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DescribeTable",
        ]
        Resource = [var.dynamodb_table_arn]
      }
    ]
  })
}

# ─────────────────────────────────────────────
# KEDA operator (IRSA)
# The KEDA operator polls SQS queue depth to drive
# autoscaling for analytics-service. It runs in the
# "keda" namespace under the "keda-operator" service
# account, so it needs its own IRSA role with SQS
# read access. TriggerAuthentication uses
# identityOwner: operator to consume this identity.
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "keda_operator_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:keda:keda-operator"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "keda_operator" {
  name               = "${var.project}-${var.environment}-keda-operator-role"
  assume_role_policy = data.aws_iam_policy_document.keda_operator_trust.json

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-keda-operator-role"
    Service = "keda"
  })
}

resource "aws_iam_role_policy" "keda_operator" {
  name = "${var.project}-${var.environment}-keda-operator-policy"
  role = aws_iam_role.keda_operator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSReadForScaling"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = [var.sqs_queue_arn]
      }
    ]
  })
}
