variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_sg_id" {
  type = string
}

variable "alb_tg_arn" {
  type = string
}

variable "secret_arn" {
  type = string
}
variable "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the database secret"
  type        = string
}

variable "image_tag" {
  description = "Tag of the application image in ECR"
  type        = string
}
