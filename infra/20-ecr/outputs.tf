output "bucket_name" {
  value       = try(aws_s3_bucket.artifacts.bucket, var.bucket_name)
  description = "Artifacts bucket name (falls back to input variable when bucket is not part of the targeted plan)"
}

output "bucket_arn" {
  value       = try(aws_s3_bucket.artifacts.arn, null)
  description = "Artifacts bucket ARN (null when bucket is not planned)"
}

output "alb_dns"               { value = aws_lb.api.dns_name }
output "tg_arn"                { value = aws_lb_target_group.api.arn }
output "tasks_security_group_id" { value = aws_security_group.tasks.id }
output "public_subnet_ids"     { value = [ for s in aws_subnet.public : s.id ] }
output "log_group_name"        { value = aws_cloudwatch_log_group.api.name }