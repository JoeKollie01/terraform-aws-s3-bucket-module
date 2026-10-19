# ShopStack prod: buckets owned by the app teams, built from the shared module.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # In a real team, state lives in a remote backend, for example:
  # backend "s3" {
  #   bucket = "shopstack-terraform-state"
  #   key    = "prod/storage/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.region
}

module "app_logs" {
  # In real life, consume a released version from Git instead of a local path:
  # source = "git::https://github.com/<you>/terraform-aws-s3-bucket-module.git//module?ref=v1.0.0"
  source = "../../module"

  project     = var.project
  environment = "prod"
  name        = "app-logs"
  owner       = "platform-team"
}

module "user_uploads" {
  source = "../../module"

  project     = var.project
  environment = "prod"
  name        = "user-uploads"
  owner       = "catalog-team"

  tags = {
    DataClass = "customer"
  }
}
