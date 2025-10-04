module "network" {
  source = "./00-network"
}

module "ecr" {
  source = "./20-ecr"
  bucket_name = var.bucket_name
}

module "ecs" {
  source = "./30-ecs-alb-mlops"
  region         = var.region
  ecr_repo       = var.ecr_repo
  image_tag      = var.image_tag
  container_port = var.container_port
  alb_sg_id      = var.alb_sg_id != "" ? var.alb_sg_id : try(module.network.alb_security_group_id, "")
  tasks_sg_id    = var.tasks_sg_id != "" ? var.tasks_sg_id : try(module.network.tasks_security_group_id, "")
  project        = var.project
  tg_arn         = module.network.tg_arn
  subnet_ids     = module.network.public_subnet_ids
  log_group_name = module.network.log_group_name
  image          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/mlops-sklearn-portfolio:latest"
  desired_count  = 1
}

// infra/main.tf （抜粋／例）
module "network" {
  source  = "./20-network"
  project = var.project
  region  = var.region
  # ここに VPC/Subnet 等の入力があれば渡す
}

data "aws_caller_identity" "current" {}
