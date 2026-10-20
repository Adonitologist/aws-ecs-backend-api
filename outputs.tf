output "alb_dns_name" {
  value = module.networking.alb_dns_name
}
output "cluster_name" {
  value = module.ecs.cluster_name
}

output "service_name" {
  value = module.ecs.service_name
}

output "ecr_repository_url" {
  value = module.ecs.repository_url
}

output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "alarm_names" {
  value = module.monitoring.alarm_names
}
