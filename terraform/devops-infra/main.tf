data "aws_caller_identity" "current" {}

# ── Shared state bucket ───────────────────────────────────────────────────────
# Single S3 bucket used by every registered pipeline. State and plan files are
# isolated by path convention:
#
#   state/<github-org>/<repo>/<workspace>/terraform.tfstate
#   plan-files/<github-org>/<repo>/run-<run_id>-<run_number>-<attempt>.tfplan
#
# Each pipeline role is granted access only to its own paths — see
# modules/pipeline-iam for the scoped S3 policies.

resource "aws_s3_bucket" "shared_state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "shared_state" {
  bucket = aws_s3_bucket.shared_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "shared_state" {
  bucket = aws_s3_bucket.shared_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "shared_state" {
  bucket = aws_s3_bucket.shared_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── GitHub Actions OIDC identity provider ────────────────────────────────────
# Created once per AWS account. If this provider already exists in your account,
# import it into this state rather than creating a second one.
#
# CLI import (Terraform 1.5 or later):
#
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com
#
# HCL import block (Terraform 1.6 or later — remove after first apply):
#
# import {
#   to = aws_iam_openid_connect_provider.github
#   id = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
# }

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    # Primary and backup thumbprints for token.actions.githubusercontent.com.
    # GitHub rotates these infrequently; verify at https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}
