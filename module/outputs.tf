output "bucket_name" {
  description = "Name (ID) of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket, for IAM policies"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name, e.g. for CloudFront origins"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
