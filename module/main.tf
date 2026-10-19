locals {
  # Company naming convention: <project>-<environment>-<name>
  bucket_name = "${var.project}-${var.environment}-${var.name}"

  # Mandatory tags are merged LAST, so callers can add tags but not overwrite these.
  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    Module      = "s3-bucket"
  })
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags

  lifecycle {
    # Catch the error at plan time instead of halfway through an apply.
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "Bucket name \"${local.bucket_name}\" is longer than the 63-character S3 limit. Shorten project or name."
    }
  }
}

# Disable ACLs: the bucket owner owns every object.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Secure by default: no public access, and NOT configurable on purpose.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # Bucket keys cut KMS request costs; irrelevant for AES256.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

# Reject any request that doesn't use HTTPS.
resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Applying a policy while the public access block is still being set
  # can fail intermittently, so wait for it.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
