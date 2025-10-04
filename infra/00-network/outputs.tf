output "alb_sg_id"         { 
  value = aws_security_group.alb.id 
  description = "Security group ID associated with the ALB (null when ALB security group is excluded from a targeted plan)"
}

output "tasks_sg_id"       { 
  value = aws_security_group.tasks.id 
  description = "Security group ID associated with the ECS tasks (null when ECS task security group is excluded from a targeted plan)"
}

output "tg_arn"            { 
  value = aws_lb_target_group.api.arn 
  description = "Target group ARN (null when target group not targeted in a partial plan)"
}

output "log_group_name"    { 
  value = aws_cloudwatch_log_group.api.name 
  description = "CloudWatch log group name (null when log group not targeted in a partial plan)"
}

output "alb_dns"           { 
  value = aws_lb.api.dns_name 
  description = "Application Load Balancer DNS name (null when ALB not targeted in a partial plan)"
}

output "alb_dns_name" {
  value       = aws_lb.api.dns_name
  description = "Application Load Balancer DNS name (deprecated; prefer alb_dns)"
}

output "alb_arn" {
  value       = aws_lb.api.arn
  description = "Application Load Balancer ARN (null when ALB not targeted in a partial plan)"
}

output "tasks_security_group_id" { value = aws_security_group.tasks.id }
output "public_subnet_ids" {
  value       = data.aws_subnets.default.ids
  description = "IDs of the default VPC subnets used by the ALB and ECS tasks"
}
