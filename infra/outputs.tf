output "bucket_name" {
  value       = try(module.ecr.bucket_name, null)
  description = "Artifacts bucket name (null when ECR/S3 module is excluded from a targeted plan)"
}

output "bucket_arn" {
  value       = try(module.ecr.bucket_arn, null)
  description = "Artifacts bucket ARN (null when ECR/S3 module is excluded from a targeted plan)"
}

output "region" {
  value = var.region
}

output "alb_dns_name" {
  value       = try(module.network.alb_dns_name, null)
  description = "Application Load Balancer DNS name (null when network module is excluded from a targeted plan)"
}

output "alb_arn" {
  value       = try(module.network.alb_arn, null)
  description = "Application Load Balancer ARN (null when network module is excluded from a targeted plan)"
}

output "tg_arn" {
  value       = try(module.network.target_group_arn, null)
  description = "Target group ARN (null when network module is excluded from a targeted plan)"
}

output "log_group_name" {
  value       = try(module.network.log_group_name, null)
  description = "CloudWatch log group name (null when network module is excluded from a targeted plan)"
}

output "tfstate_bucket" {
  value = "nickelth-tfstate"
}

output "dynamodb_lock_table" {
  value = "tf-lock"
}

output "cluster_name" {
  value       = try(module.ecs.cluster_name, null)
  description = "ECS cluster name (null when ECS module is excluded from a targeted plan)"
}

output "taskdef_arn" {
  value       = try(module.ecs.task_definition_arn, null)
  description = "ECS task definition ARN (null when ECS module is excluded from a targeted plan)"
}

output "ecs_cluster_arn" {
  value       = try(module.ecs.cluster_arn, null)
  description = "ECS cluster ARN (null when ECS module is excluded from a targeted plan)"
}

output "ecs_service_name" {
  value       = try(module.ecs.service_name, null)
  description = "ECS service name (null when ECS module is excluded from a targeted plan)"
}

output "ecr_image_uri" {
  value       = try(module.ecs.image_uri, null)
  description = "Container image URI used by ECS (null when ECS module is excluded from a targeted plan)"
}
