output "bucket_name" {
  value       = try(aws_s3_bucket.artifacts.bucket, var.bucket_name)
  description = "Artifacts bucket name (falls back to input variable when bucket is not part of the targeted plan)"
}

output "bucket_arn" {
  value       = try(aws_s3_bucket.artifacts.arn, null)
  description = "Artifacts bucket ARN (null when bucket is not planned)"
}