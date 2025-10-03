output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.api.arn
}

output "service_name" {
  value = aws_ecs_service.api.name
}

output "image_uri" {
  value = local.image_uri
}
