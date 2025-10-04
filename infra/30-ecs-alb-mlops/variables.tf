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

variable "alb_sg_id" {
  type        = string
  description = "Security group ID associated with the Application Load Balancer"
  validation {
    condition     = length(trimspace(var.alb_sg_id)) > 0
    error_message = "alb_sg_id must be a non-empty security group ID. Provide an override or allow the network module to supply it."
  }
}

variable "tasks_sg_id" {
  type        = string
  description = "Security group ID attached to the ECS tasks"
  validation {
    condition     = length(trimspace(var.tasks_sg_id)) > 0
    error_message = "tasks_sg_id must be a non-empty security group ID. Provide an override or allow the network module to supply it."
  }
}