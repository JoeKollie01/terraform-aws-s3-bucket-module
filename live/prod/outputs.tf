output "app_logs_bucket" {
  value = module.app_logs.bucket_name
}

output "user_uploads_bucket" {
  value = module.user_uploads.bucket_name
}
