output "alb_dns_name" {
  value       = try(aws_lb.api.dns_name, null)
  description = "Application Load Balancer DNS name (null when ALB not targeted in a partial plan)"
}

output "alb_arn" {
  value       = try(aws_lb.api.arn, null)
  description = "Application Load Balancer ARN (null when ALB not targeted in a partial plan)"
}

output "target_group_arn" {
  value       = try(aws_lb_target_group.api.arn, null)
  description = "Target group ARN (null when target group not targeted in a partial plan)"
}

output "log_group_name" {
  value       = try(aws_cloudwatch_log_group.api.name, null)
  description = "CloudWatch log group name (null when log group not targeted in a partial plan)"
}
