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
}

