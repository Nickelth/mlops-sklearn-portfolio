variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "mlops-sklearn-portfolio"
      Managed = "terraform"
      Env     = "dev"
    }
  }
}
