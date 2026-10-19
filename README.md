# Terraform Module Lab: A Week on the ShopStack Platform Team

A real-world, day-to-day project for **building, testing, releasing, and maintaining a Terraform module**, the way platform teams actually do it.

You'll work with a production-style AWS S3 bucket module: run its quality gate, consume it from `dev` and `prod`, ship a feature, fix a bug with test-driven development, release versions with Git tags, and wire everything into GitHub Actions CI.

**Cost:** everything except Day 2 runs **without an AWS account**. The module's tests use Terraform's `mock_provider`. Day 2 (real deployment) is optional and creates only empty S3 buckets, which cost nothing; you destroy them afterward.

---

## The scenario

You're on the **ShopStack platform team**. App teams kept creating S3 buckets by hand, and security found public buckets, missing encryption, and no tags. So the platform team built one shared module: **every bucket in the company comes from it**.

This week, you own that module. Your queue:

| Day | Task | Skill |
|---|---|---|
| 1 | Onboard: run the quality gate, read the module | `fmt`, `validate`, `terraform test`, module design |
| 2 | Deploy dev and prod from the module *(optional, AWS)* | Consuming modules, per-environment config |
| 3 | **PLAT-201:** Feature request: expire old object versions | Optional resources (`count`), new inputs, tests |
| 4 | **PLAT-202:** Bug: invalid bucket names fail mid-apply | Test-driven bug fixing, `validation`, `expect_failures` |
| 5 | Release v1.1.0 and roll it out safely | SemVer, CHANGELOG, Git tags, `?ref=` pinning |
| Bonus | Push to GitHub and watch CI run | GitHub Actions |

---

## Requirements

- **Terraform 1.7 or newer** (`terraform version`). `mock_provider` in tests arrived in 1.7.
- `make` (optional, for shortcuts) and `git`
- Day 2 only: an AWS account and credentials (`aws configure`)

---

## Repo layout

```
terraform-aws-s3-bucket-module/
├── module/                     <- THE MODULE (what you maintain)
│   ├── main.tf                 <- resources
│   ├── variables.tf            <- inputs + validation
│   ├── outputs.tf
│   ├── versions.tf             <- Terraform + provider requirements
│   ├── tests/
│   │   └── s3_bucket.tftest.hcl  <- unit tests (mocked AWS)
│   ├── README.md               <- docs for module consumers
│   └── CHANGELOG.md
├── live/                       <- CONSUMERS (how app teams use it)
│   ├── dev/
│   └── prod/
├── .github/workflows/terraform-ci.yml
├── Makefile
└── README.md                   <- this lab
```

> In a real company, `module/` and `live/` usually live in **separate repos**: the module repo publishes versions, and the live repo pins them. They're together here so the lab is self-contained.

---

## Day 1: Onboarding and the quality gate

Every change to the module must pass three checks: formatting, validation, and tests. Run them from the repo root:

```bash
make
```

Or run them by hand:

```bash
terraform fmt -check -recursive

cd module
terraform init
terraform validate
terraform test
```

You should see:

```
tests/s3_bucket.tftest.hcl... pass
  run "applies_naming_convention"... pass
  run "mandatory_tags_cannot_be_overridden"... pass
  run "secure_by_default"... pass
  run "uses_kms_when_key_provided"... pass
  run "denies_insecure_transport"... pass
  run "rejects_invalid_environment"... pass
  run "rejects_bucket_name_over_63_chars"... pass

Success! 7 passed, 0 failed.
```

### How the tests work

Open `module/tests/s3_bucket.tftest.hcl`. Each `run` block is one test:

- `mock_provider "aws" {}` replaces AWS with a fake, so **nothing is created and no credentials are needed**
- `command = plan` checks what Terraform *would* do; `command = apply` "applies" against the mock to get computed values like ARNs
- `assert` blocks are the checks
- `expect_failures` tests that bad input is **rejected**, which is just as important as testing that good input works

### Read the module

Open `module/main.tf` and find the answers to these. They're the kind of questions you'll get in a code review or interview:

1. Why are the mandatory tags merged **after** `var.tags`?
2. Why is the public access block not controlled by a variable?
3. Why does `aws_s3_bucket_policy` have `depends_on`?
4. Why does `versions.tf` say `>= 5.0` while `live/dev` says `~> 5.0`?

<details>
<summary>Answers</summary>

1. In `merge()`, later maps win. Merging mandatory tags last means a caller can add tags but can't overwrite `ManagedBy` or `Owner`. The `mandatory_tags_cannot_be_overridden` test proves it.
2. Secure by default. If it were a variable, someone would eventually set it to `false`. Public content should go through CloudFront.
3. AWS can reject a bucket policy while the public access block is still being applied. `depends_on` forces the order. Terraform can't see this dependency by itself because the policy doesn't reference the access block.
4. Modules set a **minimum** so they work in as many configurations as possible. The **root** configuration (the thing you actually run) pins the range it has tested.
</details>

### Prove the tests catch bugs

In `module/main.tf`, change `ManagedBy = "terraform"` to `ManagedBy = "tf"` and run `terraform test`. One test fails. Change it back. A test that never fails isn't testing anything.

---

## Day 2: Deploy dev and prod *(optional, needs AWS)*

S3 bucket names are **global across every AWS account**, so pick a unique prefix:

```bash
cd live/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project = "shopstack-<yourname>"  (lowercase, max 20 chars)

terraform init
terraform plan
```

Read the plan. Two module calls produce **12 resources**: each bucket comes with its ownership controls, public access block, versioning, encryption, and policy. App teams wrote 10 lines; the module did the rest.

```bash
terraform apply
```

Optionally verify in the AWS Console (S3) or with the CLI:

```bash
aws s3api get-bucket-encryption --bucket $(terraform output -raw app_logs_bucket)
aws s3api get-public-access-block --bucket $(terraform output -raw app_logs_bucket)
```

Now compare `live/dev/main.tf` with `live/prod/main.tf`. Same module, different settings: **dev** uses `force_destroy = true` so it's easy to tear down, while **prod** keeps the safe default.

Repeat in `live/prod` if you like (remember its own `terraform.tfvars`). When you're done:

```bash
terraform destroy
```

---

## Day 3: PLAT-201, expire old object versions

> **From:** catalog-team
> *"Versioning is great, but our `user-uploads` bucket keeps every old version forever and the storage bill keeps growing. Can the module delete old versions after N days? It must stay optional, and existing buckets must not change."*

### Requirements

- New input `noncurrent_version_expiration_days` (number, default `null` = keep forever)
- Must be `null` or at least `1`
- When set, create an `aws_s3_bucket_lifecycle_configuration`; when `null`, create **nothing**
- Existing callers see **no changes** in their plan

### Work like a pro: tests first

Add these to `module/tests/s3_bucket.tftest.hcl`, run `terraform test`, and **watch them fail**:

```hcl
run "no_lifecycle_rule_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "No lifecycle rule should be created unless asked for."
  }
}

run "expires_noncurrent_versions_when_set" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 30
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "Old versions must expire after the requested number of days."
  }
}

run "rejects_zero_expiration_days" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}
```

Now implement the feature until all tests pass. Hint: `count = condition ? 0 : 1` is the standard way to make a resource optional.

<details>
<summary>Solution: add to <code>module/variables.tf</code></summary>

```hcl
variable "noncurrent_version_expiration_days" {
  description = "Delete old object versions this many days after they are replaced. null = keep forever."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null || try(var.noncurrent_version_expiration_days >= 1, false)
    error_message = "noncurrent_version_expiration_days must be null or at least 1."
  }
}
```

The `try()` is needed because Terraform evaluates **both** sides of `||`, and `null >= 1` is an error.
</details>

<details>
<summary>Solution: add to <code>module/main.tf</code></summary>

```hcl
# Only created when the caller asks for it.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.noncurrent_version_expiration_days == null ? 0 : 1

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # Lifecycle rules on versions need versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.this]
}
```
</details>

Finish the ticket like you would at work:

1. Run `make` (all green, including `fmt`)
2. Add the new input to the **Inputs** table in `module/README.md`
3. Add an entry under `## [Unreleased]` in `module/CHANGELOG.md`
4. Use it: add `noncurrent_version_expiration_days = 30` to `module "user_uploads"` in `live/dev/main.tf` and run `terraform plan` there. If you deployed on Day 2, you'll see exactly **1 to add** (the lifecycle rule) and nothing else changes. If you didn't, you'll see 13 to add instead of 12.

---

## Day 4: PLAT-202, invalid bucket names fail mid-apply

> **From:** payments-team, *urgent*
> *"We set `name = "Payments_Logs"`. Plan was fine, then apply died with `InvalidBucketName`. Why didn't Terraform catch this?"*

S3 bucket names only allow lowercase letters, numbers, and hyphens. The module validates `project` but **not `name`**. Since mocked tests don't call AWS, this kind of bug only shows up in a real apply, which is exactly why input validation matters.

### Fix it test-first

**1. Reproduce the bug with a test.** Add this and run `terraform test`. It **fails**, proving the bug exists:

```hcl
run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    name = "Payments_Logs"
  }

  expect_failures = [var.name]
}
```

**2. Fix it** by adding a `validation` block to `variable "name"` in `module/variables.tf`.

<details>
<summary>Solution</summary>

```hcl
variable "name" {
  description = "What the bucket is for, e.g. app-logs. Becomes <project>-<environment>-<name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must use lowercase letters, numbers and hyphens, and start and end with a letter or number (S3 bucket naming rules)."
  }
}
```
</details>

**3. Run `terraform test` again.** All green. The test now guards against this bug ever coming back (a "regression test").

**4. Changelog:** add a `### Fixed` entry under `[Unreleased]`.

---

## Day 5: Release v1.1.0 and roll it out

### Pick the version number

| Change | Bump | Example |
|---|---|---|
| Bug fix, no new inputs | PATCH | 1.0.0 -> 1.0.1 |
| New **optional** feature | MINOR | 1.0.0 -> 1.1.0 |
| Anything that breaks callers (renamed or removed input, new **required** input, resources replaced) | MAJOR | 1.0.0 -> 2.0.0 |

This week had a new optional input (PLAT-201) and a bug fix (PLAT-202), so the release is **v1.1.0**.

> **Is PLAT-202 secretly breaking?** It could be! If any team had a bucket name with capitals, their plan would now fail. It doesn't break anyone here (S3 never allowed those names anyway), but asking this question is exactly what reviewers do.

### Cut the release

In `module/CHANGELOG.md`, rename `[Unreleased]` to `[1.1.0]` and add a fresh empty `[Unreleased]` above it. Then:

```bash
git add .
git commit -m "feat(s3-bucket): noncurrent version expiration; fix: validate bucket name"
git tag -a v1.1.0 -m "s3-bucket v1.1.0"
git push origin main --tags
```

### Roll it out: dev first, then prod

Consumers pin a version with `?ref=`:

```hcl
module "app_logs" {
  source = "git::https://github.com/<you>/terraform-aws-s3-bucket-module.git//module?ref=v1.1.0"
  # ...
}
```

The safe rollout order:

1. Bump `?ref=v1.0.0` to `?ref=v1.1.0` in **dev only**
2. `terraform init -upgrade` (needed to download the new module version) and `terraform plan`
3. Confirm the plan shows **only** the changes you expect, then apply
4. Let it run in dev, then repeat for **prod** in a separate PR

Pinning means a module change can never surprise prod. Prod upgrades only when someone deliberately bumps the ref.

---

## Bonus: Continuous integration on GitHub

`.github/workflows/terraform-ci.yml` runs the same quality gate on every pull request: `fmt`, `validate`, the mocked tests, and validation of `live/dev` and `live/prod`. It needs **no AWS credentials**.

```bash
git init
git add .
git commit -m "Initial commit: s3-bucket module v1.0.0"
git branch -M main
git remote add origin https://github.com/<you>/terraform-aws-s3-bucket-module.git
git push -u origin main
git tag -a v1.0.0 -m "s3-bucket v1.0.0"
git push origin v1.0.0
```

Then try the real workflow:

1. `git checkout -b plat-201-lifecycle`
2. Do Day 3 on that branch, push it, and open a pull request
3. Watch the **Actions** tab run the checks on your PR
4. Push a commit with bad formatting and watch CI turn red. That's the gate doing its job.

---

## Day-to-day cheat sheet

| Task | Command |
|---|---|
| Format everything | `terraform fmt -recursive` (or `make fmt`) |
| Full quality gate | `make` |
| Run one test file | `terraform test -filter=tests/s3_bucket.tftest.hcl` |
| See test detail | `terraform test -verbose` |
| Upgrade a pinned module | change `?ref=`, then `terraform init -upgrade` |
| Validate without a backend | `terraform init -backend=false && terraform validate` |

## Troubleshooting

| Problem | Fix |
|---|---|
| `Blocks of type "mock_provider" are not expected here` | Upgrade to Terraform 1.7+ |
| `BucketAlreadyExists` on apply | Bucket names are global. Choose a more unique `project` in `terraform.tfvars` |
| `No valid credential sources found` | Only Day 2 needs AWS. Run `aws configure`, or skip Day 2 |
| `Module not installed` / old module version | `terraform init` (or `terraform init -upgrade` after changing `?ref=`) |
| CI fails on format | Run `terraform fmt -recursive` locally and commit |

---

## What this project demonstrates

For anyone viewing this on GitHub: this repo shows hands-on experience with writing secure, opinionated Terraform modules; input validation and preconditions; unit testing with `terraform test` and mocked providers; test-driven bug fixing; semantic versioning and Git-tag releases; safe environment-by-environment rollouts; and CI with GitHub Actions.
