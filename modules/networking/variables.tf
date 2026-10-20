variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access the ALB (e.g., your public IP as x.x.x.x/32)"
  type        = list(string)
}