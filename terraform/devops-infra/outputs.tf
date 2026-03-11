# ── Shared infrastructure ─────────────────────────────────────────────────────

output "shared_state_bucket" {
  description = "Name of the shared S3 state bucket. Set this as the bucket value in terraform/app/backend.tf."
  value       = aws_s3_bucket.shared_state.id
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

# ── Pipeline role ARNs ────────────────────────────────────────────────────────
# Set these as GitHub repository variables under Settings → Secrets and variables → Actions → Variables.
#
# Simple mode (create_stage_specific_roles = false):
#   Set the role_arn output as AWS_ROLE_ARN.
#
# Stage-specific mode (create_stage_specific_roles = true):
#   Set role_plan_arn as AWS_ROLE_ARN_PLAN and role_apply_arn as AWS_ROLE_ARN_APPLY.

output "gh_oidc_example_default_role_arn" {
  description = "gh-to-aws-oidc-example / default workspace — set as AWS_ROLE_ARN (simple mode)."
  value       = module.gh_oidc_example_default.role_arn
}
