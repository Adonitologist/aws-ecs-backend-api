output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  value = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}
