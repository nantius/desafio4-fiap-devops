locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# DynamoDB Table — ToggleMasterAnalytics
#
# Partition key : event_id (String) — UUID generated
#                 by analytics-service at write time
#
# Attributes written per item (from analytics-service/app.py):
#   event_id  (S)
#   user_id   (S)
#   flag_name (S)
#   result    (BOOL)
#   timestamp (S)
#
# Billing: PAY_PER_REQUEST so it scales with the
# KEDA-driven analytics-service (1–5 replicas).
# ─────────────────────────────────────────────
resource "aws_dynamodb_table" "analytics" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  # ── Optional GSIs ────────────────────────────
  # GSI on user_id — supports queries like
  # "get all events for a given user"
  dynamic "global_secondary_index" {
    for_each = var.enable_user_gsi ? [1] : []
    content {
      name            = "user_id-index"
      hash_key        = "user_id"
      projection_type = "ALL"
    }
  }

  dynamic "attribute" {
    for_each = var.enable_user_gsi ? [1] : []
    content {
      name = "user_id"
      type = "S"
    }
  }

  # GSI on flag_name — supports queries like
  # "get all events for a given flag"
  dynamic "global_secondary_index" {
    for_each = var.enable_flag_gsi ? [1] : []
    content {
      name            = "flag_name-index"
      hash_key        = "flag_name"
      projection_type = "ALL"
    }
  }

  dynamic "attribute" {
    for_each = var.enable_flag_gsi ? [1] : []
    content {
      name = "flag_name"
      type = "S"
    }
  }

  # ── Point-in-time recovery ───────────────────
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  # ── Server-side encryption ───────────────────
  server_side_encryption {
    enabled = true
  }

  # ── TTL ─────────────────────────────────────
  dynamic "ttl" {
    for_each = var.ttl_attribute != "" ? [1] : []
    content {
      attribute_name = var.ttl_attribute
      enabled        = true
    }
  }

  tags = merge(local.common_tags, {
    Name    = var.table_name
    Service = "analytics-service"
  })
}
