output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}
output "kms_key_arn" {
  value = aws_kms_key.db_key.arn
}

output "db_identifier" {
  value = aws_db_instance.postgres.identifier
}
