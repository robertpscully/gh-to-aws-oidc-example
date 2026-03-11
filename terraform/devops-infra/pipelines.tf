# ── Pipeline registrations ────────────────────────────────────────────────────
# Each module call registers one pipeline — one (repo, workspace) pair.
#
# To register a new pipeline:
#   1. Add a module block below following the pattern of the existing example.
#   2. Optionally create a resource policy document at:
#        config/<github-org>/<repo-name>/<workspace-id>.json
#      If the file exists, a managed IAM policy is created from it and attached
#      to the pipeline role. Use this to grant the role access to the resources
#      it will manage (e.g. S3 buckets, Lambda functions, RDS instances).
#   3. To attach pre-existing policies instead (or in addition), add their ARNs
#      to additional_policy_arns.
#   4. Add an output for the role ARN(s) to outputs.tf.
#
# Resource policy resolution (both can be combined):
#
#   config file present → a new aws_iam_policy is created and attached
#   additional_policy_arns set → pre-existing policies attached directly

# ── gh-to-aws-oidc-example / default ─────────────────────────────────────────

locals {
  gh_oidc_example_default_policy_path = "${path.root}/config/${var.github_org}/gh-to-aws-oidc-example/default.json"
}

module "gh_oidc_example_default" {
  source = "../modules/pipeline-iam"

  github_org   = var.github_org
  repo_name    = "gh-to-aws-oidc-example"
  workspace_id = "default"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  state_bucket      = aws_s3_bucket.shared_state.id

  # In simple mode, one role covers both plan and apply. Set AWS_ROLE_ARN.
  # Set to true for separate plan (read-only) / apply (read-write) roles.
  # Then set AWS_ROLE_ARN_PLAN and AWS_ROLE_ARN_APPLY instead.
  create_stage_specific_roles = false

  role_name_prefix = "gh-oidc-example-default"

  # Load the resource policy from the config file if it exists.
  resource_policy_document = fileexists(local.gh_oidc_example_default_policy_path) ? file(local.gh_oidc_example_default_policy_path) : null

  # Attach any pre-existing managed policies by ARN.
  # Useful when the policy was created outside this root module.
  additional_policy_arns = []
}
