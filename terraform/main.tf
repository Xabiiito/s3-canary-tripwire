terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for the tripwire resources"
  type        = string
  default     = "eu-west-1"
}

variable "alert_email" {
  description = "Email address to receive tripwire alerts"
  type        = string
  default     = "security-alerts@example.com"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 1. Private S3 Bucket for the canary asset
resource "aws_s3_bucket" "tripwire_bucket" {
  bucket        = "prod-internal-backups-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Project     = "s3-canary-tripwire"
    Environment = "detection-lab"
  }
}

resource "aws_s3_bucket_public_access_block" "tripwire_block" {
  bucket = aws_s3_bucket.tripwire_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tripwire_sse" {
  bucket = aws_s3_bucket.tripwire_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 2. Decoy file (Honeytoken) inside the bucket
resource "aws_s3_object" "canary_secret" {
  bucket       = aws_s3_bucket.tripwire_bucket.id
  key          = "keys/aws_root_backup_credentials.json"
  content_type = "application/json"
  content = jsonencode({
    warning         = "CANARY_TRIPWIRE_ASSET_MONITORED"
    aws_access_key  = "AKIAIOSFODNN7CANARY0"
    aws_secret_key  = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYCANARYKEY"
    note            = "Fictitious honey-credential for unauthorized access detection"
  })
}

# 3. SNS Topic & Subscription for Alerting
resource "aws_sns_topic" "tripwire_alerts" {
  name = "s3-canary-tripwire-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.tripwire_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 4. EventBridge Rule catching GetObject on the specific canary key
resource "aws_cloudwatch_event_rule" "canary_access_rule" {
  name        = "detect-s3-canary-access"
  description = "Triggers when the S3 canary object is read via GetObject"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["GetObject"]
      requestParameters = {
        bucketName = [aws_s3_bucket.tripwire_bucket.id]
        key        = [aws_s3_object.canary_secret.key]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.canary_access_rule.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.tripwire_alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.tripwire_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.tripwire_alerts.arn
      }
    ]
  })
}

output "bucket_name" {
  description = "Name of the created S3 canary bucket"
  value       = aws_s3_bucket.tripwire_bucket.id
}

output "canary_object_key" {
  description = "Key path of the decoy file"
  value       = aws_s3_object.canary_secret.key
}