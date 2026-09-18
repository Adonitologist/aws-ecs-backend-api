# generate secure password
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# secrets manager configuration
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "rds-db-credentials-${var.environment}"
  recovery_window_in_days = 0
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

# rds subnet group
resource "aws_db_subnet_group" "default" {
  name       = "main-db-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

# rds instance
resource "aws_db_instance" "postgres" {
  identifier             = "ecs-backend-db-${var.environment}"
  engine                 = "postgres"
  engine_version         = "15.8"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "appdb"
  username               = "dbadmin"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [var.db_sg_id]
  skip_final_snapshot    = true
  publicly_accessible    = false
}