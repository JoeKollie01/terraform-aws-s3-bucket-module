variable "project" {
  description = "Your unique prefix. S3 bucket names are global, so make it yours, e.g. shopstack-jdoe"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
