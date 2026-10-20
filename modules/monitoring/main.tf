# No subscription on purpose: nobody can confirm one. Alarm actions publish to the topic only.
data "aws_caller_identity" "current" {}

# CloudWatch alarms cannot publish to a topic encrypted with the AWS managed key, hence a customer managed key.
resource "aws_kms_key" "sns" {
  description             = "KMS key for the alarms SNS topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "Allow CloudWatch Alarms to publish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_sns_topic" "alarms" {
  name              = "alarms-${var.environment}"
  kms_master_key_id = aws_kms_key.sns.id
}

locals {
  alb_dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }

  alarms = {
    unhealthy_hosts = {
      alarm_name          = "alb-unhealthy-hosts-${var.environment}"
      namespace           = "AWS/ApplicationELB"
      metric_name         = "UnHealthyHostCount"
      statistic           = "Maximum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      evaluation_periods  = 1
      dimensions          = local.alb_dimensions
    }
    target_5xx = {
      alarm_name          = "alb-target-5xx-${var.environment}"
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_Target_5XX_Count"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 5
      evaluation_periods  = 1
      dimensions          = local.alb_dimensions
    }
    ecs_cpu_high = {
      alarm_name          = "ecs-cpu-high-${var.environment}"
      namespace           = "AWS/ECS"
      metric_name         = "CPUUtilization"
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 2
      dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
    }
    rds_cpu_high = {
      alarm_name          = "rds-cpu-high-${var.environment}"
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 2
      dimensions          = { DBInstanceIdentifier = var.db_identifier }
    }
    rds_free_storage_low = {
      alarm_name          = "rds-free-storage-low-${var.environment}"
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = 2147483648 # 2 GiB of the 20 GiB allocated
      evaluation_periods  = 1
      dimensions          = { DBInstanceIdentifier = var.db_identifier }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = each.value.alarm_name
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  period              = 60
  dimensions          = each.value.dimensions
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
