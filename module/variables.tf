variable "project" {
  description = "Project or company prefix used in the bucket name, e.g. shopstack"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project))
    error_message = "project must be 2-20 characters: lowercase letters, numbers and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name" {
  description = "What the bucket is for, e.g. app-logs. Becomes <project>-<environment>-<name>."
  type        = string
}

variable "owner" {
  description = "Team that owns the bucket (used for tagging and cost reports)"
  type        = string
}

variable "versioning_enabled" {
  description = "Keep previous versions of objects. Strongly recommended for anything you can't recreate."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption. Leave null to use S3-managed keys (AES256)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a bucket that still has objects. Only use in dev."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags. The mandatory tags (Project, Environment, Owner, ManagedBy) cannot be overridden."
  type        = map(string)
  default     = {}
}
