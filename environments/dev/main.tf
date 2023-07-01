provider "aws" {
  region = "us-east-2"
}

terraform {
  required_version = "0.12.26"

  backend "s3" {
    bucket         = "featherai-terraform-state"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-2"
  }
}

module "core" {
    source              = "../../modules/core"
    prefix              = var.prefix
    region              = var.region
    storage_main        = "feather-ai-dev-front-storage"
    availability_zone_a   = var.availability_zone_a
    availability_zone_b   = var.availability_zone_b
    db_password           = var.db_password
    stripe_secret_key     = var.stripe_secret_key
    stripe_webhook_secret_key = var.stripe_webhook_secret_key
    model_jwt_secret_key = var.model_jwt_secret_key
}
