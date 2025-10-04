data "aws_lb" "api" {
  name = aws_lb.api.name
}

data "aws_lb_target_group" "api" {
  arn = aws_lb_target_group.api.arn
}

data "aws_cloudwatch_log_group" "api" {
  name = aws_cloudwatch_log_group.api.name
}

data "aws_security_group" "alb" {
  id = aws_security_group.alb.id
}

data "aws_security_group" "tasks" {
  id = aws_security_group.tasks.id
}