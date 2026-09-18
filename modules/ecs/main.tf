# ecs cluster
resource "aws_ecs_cluster" "main" {
  name = "app-cluster-${var.environment}"
}

# iam roles for ecs task execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# grant permission to read secrets manager from execution role
resource "aws_iam_policy" "secrets_policy" {
  name = "ecs-secrets-policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

# cloudwatch log group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/app-${var.environment}"
  retention_in_days = 7
}

# fargate task definition
resource "aws_ecs_task_definition" "app" {
  family                   = "app-task-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "hashicorp/http-echo:latest"
      command   = [
        "-text=<!DOCTYPE html><html><body style='font-family: system-ui, sans-serif; text-align: center; padding: 4%; background-color: #f8f9fa;'><h1 style='color: #232f3e; margin-bottom: 10px;'>Hello, I am Juan Eslava Herraiz</h1><p style='color: #444; max-width: 650px; margin: 0 auto 20px auto; font-size: 16px; line-height: 1.6;'>If you are seeing this page, the enterprise-grade AWS infrastructure is fully operational. This confirms that traffic is successfully routing from the public Internet, passing through an Application Load Balancer (ALB), traversing secure Security Groups, and reaching this serverless Amazon ECS Fargate container running inside an isolated Private Subnet.</p><a href='https://github.com/Adonitologist' target='_blank' style='display: inline-block; margin-bottom: 30px; padding: 10px 20px; background-color: #24292e; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold; font-size: 14px;'>Visit my GitHub</a><div style='display: flex; justify-content: center; gap: 20px; flex-wrap: wrap; max-width: 1050px; margin: 0 auto;'><div style='flex: 1; min-width: 280px; background: #ffffff; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); border: 1px solid #e1e4e8;'><h3 style='color: #232f3e; margin-top: 0; font-size: 15px; border-bottom: 2px solid #eaecef; padding-bottom: 8px;'>API Runtime Specifications</h3><table style='width: 100%; border-collapse: collapse; font-size: 13px; text-align: left;'><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Compute</th><td style='padding: 6px; color: #24292e;'>AWS Fargate</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Protocol</th><td style='padding: 6px; color: #24292e;'>HTTP / REST</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Port</th><td style='padding: 6px; color: #24292e;'>8080 TCP</td></tr><tr><th style='padding: 6px; color: #586069;'>Database</th><td style='padding: 6px; color: #24292e;'>RDS PostgreSQL 15</td></tr></table></div><div style='flex: 1; min-width: 280px; background: #ffffff; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); border: 1px solid #e1e4e8;'><h3 style='color: #232f3e; margin-top: 0; font-size: 15px; border-bottom: 2px solid #eaecef; padding-bottom: 8px;'>Auto Scaling Configuration</h3><table style='width: 100%; border-collapse: collapse; font-size: 13px; text-align: left;'><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Min Capacity</th><td style='padding: 6px; color: #24292e;'>1 Task</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Max Capacity</th><td style='padding: 6px; color: #24292e;'>4 Tasks</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>CPU Target</th><td style='padding: 6px; color: #24292e;'>75.0%</td></tr><tr><th style='padding: 6px; color: #586069;'>Memory Target</th><td style='padding: 6px; color: #24292e;'>75.0%</td></tr></table></div><div style='flex: 1; min-width: 280px; background: #ffffff; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); border: 1px solid #e1e4e8;'><h3 style='color: #232f3e; margin-top: 0; font-size: 15px; border-bottom: 2px solid #eaecef; padding-bottom: 8px;'>Network & Security Topology</h3><table style='width: 100%; border-collapse: collapse; font-size: 13px; text-align: left;'><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>VPC CIDR</th><td style='padding: 6px; color: #24292e;'>10.0.0.0/16</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Subnets</th><td style='padding: 6px; color: #24292e;'>4 (2 Public, 2 Private)</td></tr><tr style='border-bottom: 1px solid #eaecef;'><th style='padding: 6px; color: #586069;'>Secrets</th><td style='padding: 6px; color: #24292e;'>AWS Secrets Manager</td></tr><tr><th style='padding: 6px; color: #586069;'>Logging</th><td style='padding: 6px; color: #24292e;'>CloudWatch (7 Days)</td></tr></table></div></div></body></html>",
        "-listen=:8080"
      ]
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
      secrets = [
        {
          name      = "DB_CREDENTIALS"
          valueFrom = var.secret_arn
        }
      ]
    }
  ])
}

# ecs service
resource "aws_ecs_service" "app" {
  name            = "app-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_tg_arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [var.alb_tg_arn]
}


# application autoscaling target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# cpu based autoscaling policy
resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# memory based autoscaling policy
resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  name               = "memory-autoscaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}