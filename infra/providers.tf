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