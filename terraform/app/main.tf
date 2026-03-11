# ── Example resources ─────────────────────────────────────────────────────────
# Replace these with your own infrastructure. The resources here are deployed
# by the GitHub Actions pipeline defined in .github/workflows/terraform.yml.
#
# IAM permissions for whatever you put here are managed in devops-infra:
#   1. Write a policy document to:
#        terraform/devops-infra/config/<github-org>/<repo-name>/<workspace-id>.json
#   2. Apply terraform/devops-infra to create and attach the policy to the role.

resource "aws_s3_bucket" "example" {
  bucket = "s3bucket-a092eifjoqek"
}

resource "time_static" "created_at" {}

resource "aws_s3_object" "hello" {
  count   = 3
  bucket  = aws_s3_bucket.example.id
  key     = "${time_static.created_at.rfc3339}-${count.index}"
  content = "HELLO ROB @ ${time_static.created_at.rfc3339}"
}
