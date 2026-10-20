variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB on port 80. Set it in terraform.tfvars (git-ignored), e.g. your public IP as x.x.x.x/32."
  type        = list(string)
}

variable "image_tag" {
  description = "Tag of the application image in ECR (tags are immutable)"
  type        = string
  default     = "v1"
}
