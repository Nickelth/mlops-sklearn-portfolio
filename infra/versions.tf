terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  backend "s3" {
    bucket         = "nickelth-tfstate"
    key            = "mlops-sklearn-portfolio/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "tf-lock"
    encrypt        = true
  }
}
