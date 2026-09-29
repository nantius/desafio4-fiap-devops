locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# Dead-Letter Queue
# Messages that fail processing by analytics-service
# after var.max_receive_count attempts are moved here.
# ─────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.queue_name}-dlq"
  message_retention_seconds  = var.dlq_message_retention_seconds
  kms_master_key_id          = "alias/aws/sqs"

  tags = merge(local.common_tags, {
    Name    = "${var.queue_name}-dlq"
    Service = "analytics-service"
  })
}

# ─────────────────────────────────────────────
# Main SQS Queue — evaluation_service_queue
#
# Producer : evaluation-service  (SendMessage)
# Consumer : analytics-service   (ReceiveMessage / DeleteMessage)
# Scaler   : KEDA ScaledObject   (GetQueueAttributes)
# ─────────────────────────────────────────────
resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size_bytes
  delay_seconds              = 0
  receive_wait_time_seconds  = 20  # Long-polling — matches analytics-service app.py WaitTimeSeconds

  # Server-side encryption with the AWS-managed SQS key
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_tags, {
    Name    = var.queue_name
    Service = "evaluation-service analytics-service"
  })
}

# ─────────────────────────────────────────────
# Queue Policy
# Restricts SendMessage to the evaluation-service
# IAM role and ReceiveMessage/DeleteMessage to the
# analytics-service IAM role.
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "sqs_policy" {
  # Allow evaluation-service to send messages
  statement {
    sid    = "AllowProducerSend"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.producer_role_arns
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this.arn]
  }

  # Allow analytics-service (consumer) and KEDA to interact with the queue
  statement {
    sid    = "AllowConsumerReceive"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.consumer_role_arns
    }

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.this.arn]
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.sqs_policy.json
}
