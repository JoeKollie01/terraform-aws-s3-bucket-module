# Unit tests for the module. Run from the module folder:  terraform test
# mock_provider means NO AWS account or credentials are needed, and nothing is created.

mock_provider "aws" {}

# Default inputs for every run block below (each run can override them).
variables {
  project     = "shopstack"
  environment = "dev"
  name        = "app-logs"
  owner       = "platform-team"
}

run "applies_naming_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "shopstack-dev-app-logs"
    error_message = "Bucket name must follow <project>-<environment>-<name>."
  }
}

run "mandatory_tags_cannot_be_overridden" {
  command = plan

  variables {
    tags = {
      ManagedBy  = "clickops"
      CostCenter = "1234"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["ManagedBy"] == "terraform"
    error_message = "Callers must not be able to override the ManagedBy tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["CostCenter"] == "1234"
    error_message = "Extra tags from the caller must be kept."
  }
}

run "secure_by_default" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled by default."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm]) == "AES256"
    error_message = "Default encryption must be AES256 when no KMS key is given."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false."
  }
}

run "uses_kms_when_key_provided" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm]) == "aws:kms"
    error_message = "Encryption must switch to aws:kms when a key is given."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.bucket_key_enabled]) == true
    error_message = "Bucket keys must be enabled with KMS to reduce cost."
  }
}

run "denies_insecure_transport" {
  # apply (against the mock) so the bucket ARN in the policy is known
  command = apply

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Bucket policy must deny requests that don't use HTTPS."
  }
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_bucket_name_over_63_chars" {
  command = plan

  variables {
    name = "this-name-is-way-too-long-for-an-s3-bucket-honestly-it-is"
  }

  expect_failures = [aws_s3_bucket.this]
}
