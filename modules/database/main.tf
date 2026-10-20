data "aws_caller_identity" "current" {}

resource "aws_kms_key" "db_key" {
  description             = "KMS customer managed key for RDS and Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
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

# Accepted risk: the stack must be fully destroyable. No deletion protection, no automated backups, no final snapshot.
# tfsec:ignore:aws-rds-specify-backup-retention
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
  skip_final_snapshot                 = true
  publicly_accessible                 = false
  storage_encrypted                   = true
  storage_type                        = "gp3"
  kms_key_id                          = aws_kms_key.db_key.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = 0
  # tfsec:ignore:aws-rds-enable-deletion-protection
  deletion_protection             = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.db_key.arn
}