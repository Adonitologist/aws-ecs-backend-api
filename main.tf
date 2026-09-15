module "networking" {
  source      = "./modules/networking"
  vpc_cidr    = var.vpc_cidr
  environment = var.environment
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
}