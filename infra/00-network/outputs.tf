output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "alb_arn" {
  value = aws_lb.api.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}
