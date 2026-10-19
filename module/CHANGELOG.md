# Changelog

All notable changes to this module. Versions follow [Semantic Versioning](https://semver.org/):
MAJOR = breaking change, MINOR = new feature (backwards compatible), PATCH = bug fix.

## [Unreleased]

## [1.0.0]

### Added
- S3 bucket following the `<project>-<environment>-<name>` naming convention
- Mandatory tags (Project, Environment, Owner, ManagedBy, Module) that callers cannot override
- Public access block (always on), ACLs disabled (BucketOwnerEnforced)
- Versioning (on by default)
- Encryption: AES256 by default, KMS when `kms_key_arn` is set
- Bucket policy denying non-HTTPS requests
- Plan-time check for the 63-character bucket name limit
- Unit tests with a mocked AWS provider
