output "bucket_name" {
  value = module.ecr.bucket_name
}

output "bucket_arn" {
  value = module.ecr.bucket_arn
}

output "region" {
  value = var.region
}

output "alb_dns_name" {
  value = module.network.alb_dns_name
}

output "alb_arn" {
  value = module.network.alb_arn
}

output "tg_arn" {
  value = module.network.target_group_arn
}

output "log_group_name" {
  value = module.network.log_group_name
}

output "tfstate_bucket" {
  value = "nickelth-tfstate"
}

output "dynamodb_lock_table" {
  value = "tf-lock"
}

output "cluster_name" {
  value = module.ecs.cluster_name
}

output "taskdef_arn" {
  value = module.ecs.task_definition_arn
}

output "ecs_cluster_arn" {
  value = module.ecs.cluster_arn
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "ecr_image_uri" {
  value = module.ecs.image_uri
}
