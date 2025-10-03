locals {
  ecr_repository_uri = can(regex(".amazonaws.com/", var.ecr_repo)) ? var.ecr_repo : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo}"
  image_uri = "${local.ecr_repository_uri}:${var.image_tag}"
}

output "bucket_name" { value = aws_s3_bucket.artifacts.bucket }
output "bucket_arn" { value = aws_s3_bucket.artifacts.arn }
output "region" { value = var.region }
output "alb_dns_name" { value = aws_lb.api.dns_name }
output "alb_arn" { value = aws_lb.api.arn }
output "tg_arn" { value = aws_lb_target_group.api.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.api.name }
output "tfstate_bucket" { value = "nickelth-tfstate" }
output "dynamodb_lock_table" { value = "tf-lock" }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "taskdef_arn" { value = aws_ecs_task_definition.api.arn }
output "ecs_cluster_arn"  { value = aws_ecs_cluster.this.arn }
output "ecs_service_name" { value = aws_ecs_service.api.name }
output "ecr_image_uri"    { value = local.image_uri }
output "alb_dns_name" { value = module.network.alb_dns_name }