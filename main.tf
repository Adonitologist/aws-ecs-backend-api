module "networking" {
  source      = "./modules/networking"
  vpc_cidr    = var.vpc_cidr
  environment = var.environment

  allowed_ingress_cidrs = var.allowed_ingress_cidrs
}

module "database" {
  source             = "./modules/database"
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnets
  db_sg_id           = module.networking.db_sg_id
}

module "ecs" {
  source             = "./modules/ecs"
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnets
  ecs_sg_id          = module.networking.ecs_sg_id
  alb_tg_arn         = module.networking.alb_tg_arn
  secret_arn         = module.database.secret_arn
  kms_key_arn        = module.database.kms_key_arn
  image_tag          = var.image_tag
}

module "monitoring" {
  source         = "./modules/monitoring"
  environment    = var.environment
  alb_arn_suffix = module.networking.alb_arn_suffix
  tg_arn_suffix  = module.networking.tg_arn_suffix
  cluster_name   = module.ecs.cluster_name
  service_name   = module.ecs.service_name
  db_identifier  = module.database.db_identifier
}
