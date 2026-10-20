output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "service_name" {
  value = aws_ecs_service.app.name
}