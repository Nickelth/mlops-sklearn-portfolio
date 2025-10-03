variable "project" {
  type        = string
  default     = "mlops-sklearn-portfolio"
  description = "Project name for tagging/prefixing"
}

variable "ecr_repository_url" {
  type        = string
  default     = ""
  description = "ECR repository URI, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com/mlops-sklearn-portfolio"
}