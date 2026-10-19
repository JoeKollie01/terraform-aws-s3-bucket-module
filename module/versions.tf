terraform {
  # 1.7+ is needed for mock providers in `terraform test`
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Modules set a MINIMUM version only. The calling configuration
      # (live/dev, live/prod) pins the exact range it wants.
      version = ">= 5.0"
    }
  }
}
