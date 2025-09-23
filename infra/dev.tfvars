project       = "mlops-sklearn-portfolio"
region        = "us-west-2"
bucket_name   = "nickelth-mlops-artifacts"
force_destroy = false
ecr_repo       = "<ECR_REGISTRY>/mlops-sklearn-portfolio"
image_tag      = "latest"
container_port = 8000
