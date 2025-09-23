resource "aws_cloudwatch_log_group" "api" {
  name              = "/mlops/api"
  retention_in_days = 14
}
