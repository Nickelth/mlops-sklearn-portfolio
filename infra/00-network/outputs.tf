output "alb_dns" {
  value       = try(data.aws_lb.api.dns_name, null)
  description = "Application Load Balancer DNS name (null when ALB not targeted in a partial plan)"
}

output "alb_dns_name" {
  value       = try(data.aws_lb.api.dns_name, null)
  description = "Application Load Balancer DNS name (deprecated; prefer alb_dns)"
}


output "alb_arn" {
  value       = try(data.aws_lb.api.arn, null)
  description = "Application Load Balancer ARN (null when ALB not targeted in a partial plan)"
}

output "target_group_arn" {
  value       = try(data.aws_lb_target_group.api.arn, null)
  description = "Target group ARN (null when target group not targeted in a partial plan)"
}

output "log_group_name" {
  value       = try(data.aws_cloudwatch_log_group.api.name, null)
  description = "CloudWatch log group name (null when log group not targeted in a partial plan)"
}

output "alb_security_group_id" {
  value       = try(data.aws_security_group.alb.id, null)
  description = "Security group ID associated with the ALB (null when ALB security group is excluded from a targeted plan)"
}

output "tasks_security_group_id" {
  value       = try(data.aws_security_group.tasks.id, null)
  description = "Security group ID associated with the ECS tasks (null when ECS task security group is excluded from a targeted plan)"
}
