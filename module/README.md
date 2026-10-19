# s3-bucket module

An opinionated, secure-by-default S3 bucket for ShopStack teams.

Every bucket gets: a standard name, mandatory tags, no public access, ACLs disabled, encryption, versioning, and HTTPS-only access. Teams choose *what the bucket is for*; the platform team decides *how it's secured*.

## Usage

```hcl
module "app_logs" {
  source = "git::https://github.com/<you>/terraform-aws-s3-bucket-module.git//module?ref=v1.0.0"

  project     = "shopstack"
  environment = "prod"
  name        = "app-logs"
  owner       = "platform-team"
}
```

Creates the bucket `shopstack-prod-app-logs`.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `project` | Prefix for the bucket name (2-20 chars, lowercase) | `string` | n/a | yes |
| `environment` | `dev`, `staging`, or `prod` | `string` | n/a | yes |
| `name` | What the bucket is for, e.g. `app-logs` | `string` | n/a | yes |
| `owner` | Owning team, used for tagging and cost reports | `string` | n/a | yes |
| `versioning_enabled` | Keep previous object versions | `bool` | `true` | no |
| `kms_key_arn` | KMS key ARN; `null` uses AES256 | `string` | `null` | no |
| `force_destroy` | Allow destroying a non-empty bucket (dev only) | `bool` | `false` | no |
| `tags` | Extra tags (mandatory tags can't be overridden) | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `bucket_name` | Name (ID) of the bucket |
| `bucket_arn` | ARN, for IAM policies |
| `bucket_regional_domain_name` | Regional domain name, e.g. for CloudFront |

## Design decisions

- **Public access is not configurable.** Public content should go through CloudFront, not a public bucket.
- **Mandatory tags are merged last**, so finance and security reports can trust them.
- **Only a minimum AWS provider version** (`>= 5.0`) is set here. The calling configuration pins the exact range.
- **The 63-character name limit is checked at plan time** with a `precondition`, so it fails before anything is created.

## Testing

```bash
terraform init
terraform test
```

Tests use `mock_provider`, so they need no AWS credentials and create nothing.

> Tip: in a real repo, generate the Inputs/Outputs tables automatically with [terraform-docs](https://terraform-docs.io/).
