locals {
  # ── Path convention ───────────────────────────────────────────────────────
  # These locals derive S3 paths from the pipeline identity (org/repo/workspace).
  # They mirror the PLAN_KEY and backend key set in the GitHub Actions workflow,
  # so IAM policies are always scoped to exactly what the pipeline can access.
  #
  #   state key:    state/<org>/<repo>/<workspace>/terraform.tfstate
  #   plan prefix:  plan-files/<org>/<repo>/*   (scoped to repo, not global)

  state_key    = "state/${var.github_org}/${var.repo_name}/${var.workspace_id}/terraform.tfstate"
  plan_prefix  = "plan-files/${var.github_org}/${var.repo_name}/*"

  # ── OIDC subject claim ────────────────────────────────────────────────────
  # Restricts role assumption to workflows in this specific repository.
  # The wildcard covers all branches, tags, and event types.
  subject_claim = "repo:${var.github_org}/${var.repo_name}:*"

  # ── Role configurations ───────────────────────────────────────────────────
  # Drives all role resources via for_each, keeping resource blocks identical
  # regardless of which mode is active.
  #
  # Simple mode   → one key ("terraform") with full state + plan file access
  # Advanced mode → two keys ("plan" / "apply") with scoped access per stage
  role_configs = var.create_stage_specific_roles ? {
    plan = {
      suffix    = "plan"
      s3_policy = data.aws_iam_policy_document.s3_plan.json
    }
    apply = {
      suffix    = "apply"
      s3_policy = data.aws_iam_policy_document.s3_apply.json
    }
  } : {
    terraform = {
      suffix    = "terraform"
      s3_policy = data.aws_iam_policy_document.s3_full.json
    }
  }

  # ── Policy ARNs to attach ─────────────────────────────────────────────────
  # Combines the policy created from resource_policy_document (if any) with
  # any pre-existing policies supplied via additional_policy_arns.
  all_policy_arns = concat(
    [for p in aws_iam_policy.resource_access : p.arn],
    var.additional_policy_arns,
  )

  # Cartesian product of role keys × policy ARNs for the attachment resource.
  role_policy_attachments = {
    for pair in setproduct(keys(local.role_configs), local.all_policy_arns) :
    "${pair[0]}__${pair[1]}" => {
      role_key   = pair[0]
      policy_arn = pair[1]
    }
  }
}

# ── OIDC trust policy ─────────────────────────────────────────────────────────
# Shared by all roles created by this module. Restricts assumption to the
# nominated repository so that no other GitHub repository can assume these roles.

data "aws_iam_policy_document" "oidc_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.subject_claim]
    }
  }
}

# ── S3 policy: plan stage (read state, write plan file) ───────────────────────

data "aws_iam_policy_document" "s3_plan" {
  # Bucket-level: allow listing, scoped to this pipeline's paths.
  # StringLikeIfExists is used so that list calls without a prefix
  # (e.g. bucket-existence checks) are not incorrectly denied.
  statement {
    sid     = "StateBucketAccess"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values = [
        "state/${var.github_org}/${var.repo_name}/${var.workspace_id}/*",
        "plan-files/${var.github_org}/${var.repo_name}/*",
      ]
    }
  }

  # Object-level: read the state file for this workspace only.
  statement {
    sid       = "StateObjectRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.state_key}"]
  }

  # Object-level: write plan files scoped to this repository.
  statement {
    sid       = "PlanFileWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.plan_prefix}"]
  }
}

# ── S3 policy: apply stage (read/write state, read/delete plan file) ──────────

data "aws_iam_policy_document" "s3_apply" {
  statement {
    sid     = "StateBucketAccess"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values = [
        "state/${var.github_org}/${var.repo_name}/${var.workspace_id}/*",
        "plan-files/${var.github_org}/${var.repo_name}/*",
      ]
    }
  }

  statement {
    sid       = "StateObjectReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.state_key}"]
  }

  statement {
    sid       = "PlanFileReadDelete"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.plan_prefix}"]
  }
}

# ── S3 policy: full access (simple mode — plan + apply combined) ──────────────

data "aws_iam_policy_document" "s3_full" {
  statement {
    sid     = "StateBucketAccess"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values = [
        "state/${var.github_org}/${var.repo_name}/${var.workspace_id}/*",
        "plan-files/${var.github_org}/${var.repo_name}/*",
      ]
    }
  }

  statement {
    sid       = "StateObjectReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.state_key}"]
  }

  statement {
    sid       = "PlanFileReadWriteDelete"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${local.plan_prefix}"]
  }
}

# ── Resource access policy ────────────────────────────────────────────────────
# Created only when resource_policy_document is provided. The document is
# loaded from a per-workspace JSON file in devops-infra/config/ and describes
# the AWS resource permissions the pipeline needs to do its work.

resource "aws_iam_policy" "resource_access" {
  count = var.resource_policy_document != null ? 1 : 0

  name        = "${var.role_name_prefix}-resource-access"
  description = "Resource permissions for the ${var.github_org}/${var.repo_name}/${var.workspace_id} pipeline"
  policy      = var.resource_policy_document
}

# ── IAM roles ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "roles" {
  for_each = local.role_configs

  name               = "${var.role_name_prefix}-${each.value.suffix}"
  assume_role_policy = data.aws_iam_policy_document.oidc_trust.json
}

# ── Inline S3 policy per role ─────────────────────────────────────────────────

resource "aws_iam_role_policy" "s3" {
  for_each = local.role_configs

  name   = "terraform-state-access"
  role   = aws_iam_role.roles[each.key].id
  policy = each.value.s3_policy
}

# ── Managed policy attachments ────────────────────────────────────────────────
# Attaches both the created resource-access policy (if any) and any pre-existing
# policies provided via additional_policy_arns.

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.role_policy_attachments

  role       = aws_iam_role.roles[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
