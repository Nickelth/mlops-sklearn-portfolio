variable "bucket_name" {
  type        = string
  description = "Global-unique S3 bucket name for artifacts/models/logs"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow bucket force destroy (dev only; usually false)"
}

variable "project"     { type = string }
variable "region"      { type = string }
variable "bucket_name" { type = string }
