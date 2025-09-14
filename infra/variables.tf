variable "project" {
  type        = string
  default     = "mlops-sklearn-portfolio"
  description = "Project name for tagging/prefixing"
}

variable "bucket_name" {
  type        = string
  description = "Global-unique S3 bucket name for artifacts/models/logs"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow bucket force destroy (dev only; usually false)"
}

variable "region" {
  type = string
  description = "AWS region (e.g. us-west-2)"
}
