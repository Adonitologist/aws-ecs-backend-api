resource "aws_kms_key" "db_key" {
  description             = "KMS customer managed key for RDS and Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "rds-db-credentials-${var.environment}"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.db_key.arn
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_password.result
    engine   = "postgres"
    port     = 5432
    host     = aws_db_instance.postgres.address
  })
}

resource "aws_db_subnet_group" "default" {
  name       = "main-db-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "postgres" {
  identifier                          = "ecs-backend-db-${var.environment}"
  engine                              = "postgres"
  engine_version                      = "15.8"
  instance_class                      = "db.t3.micro"
  allocated_storage                   = 20
  max_allocated_storage               = 100
  db_name                             = "appdb"
  username                            = "dbadmin"
  password                            = random_password.db_password.result
  db_subnet_group_name                = aws_db_subnet_group.default.name
  vpc_security_group_ids              = [var.db_sg_id]
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "ecs-backend-db-final-snapshot-${var.environment}"
  publicly_accessible                 = false
  storage_encrypted                   = true
  storage_type                        = "gp3"
  kms_key_id                          = aws_kms_key.db_key.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = 7
  deletion_protection                 = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.db_key.arn
}