output "cluster_name" {
  value       = try(aws_ecs_cluster.this.name, null)
  description = "Name of the ECS cluster (null when the cluster is excluded from a targeted plan)"
}

output "cluster_arn" {
  value       = try(aws_ecs_cluster.this.arn, null)
  description = "ARN of the ECS cluster (null when the cluster is excluded from a targeted plan)"
}

output "task_definition_arn" {
  value       = try(aws_ecs_task_definition.api.arn, null)
  description = "ARN of the ECS task definition (null when the task definition is excluded from a targeted plan)"
}

output "service_name" {
  value       = try(aws_ecs_service.api.name, null)
  description = "Name of the ECS service (null when the service is excluded from a targeted plan)"
}

output "image_uri" {
  value       = try(local.image_uri, null)
  description = "Container image URI used by the ECS task (null when image URI cannot be resolved)"
}

output "alb_security_group_id" {
  value       = var.alb_sg_id
  description = "Security group ID associated with the Application Load Balancer"
}

output "tasks_security_group_id" {
  value       = var.tasks_sg_id
  description = "Security group ID associated with the ECS tasks"
}