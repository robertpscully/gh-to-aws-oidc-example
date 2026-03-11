# ── Simple mode ───────────────────────────────────────────────────────────────
# Set when create_stage_specific_roles = false.
# Use role_arn as AWS_ROLE_ARN in GitHub repository variables.

output "role_arn" {
  description = "ARN of the single Terraform role (simple mode). Set as AWS_ROLE_ARN in GitHub repository variables."
  value       = try(aws_iam_role.roles["terraform"].arn, null)
}

# ── Stage-specific mode ───────────────────────────────────────────────────────
# Set when create_stage_specific_roles = true.
# Use role_plan_arn as AWS_ROLE_ARN_PLAN and role_apply_arn as AWS_ROLE_ARN_APPLY.

output "role_plan_arn" {
  description = "ARN of the plan-stage (read-only) role (stage-specific mode). Set as AWS_ROLE_ARN_PLAN."
  value       = try(aws_iam_role.roles["plan"].arn, null)
}

output "role_apply_arn" {
  description = "ARN of the apply-stage (read-write) role (stage-specific mode). Set as AWS_ROLE_ARN_APPLY."
  value       = try(aws_iam_role.roles["apply"].arn, null)
}

# ── Resource access policy ────────────────────────────────────────────────────

output "resource_access_policy_arn" {
  description = "ARN of the resource-access policy created from resource_policy_document, or null if no document was provided."
  value       = try(aws_iam_policy.resource_access[0].arn, null)
}
