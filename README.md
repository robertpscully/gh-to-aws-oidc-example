# gh-to-aws-oidc-example

A reference implementation demonstrating how to replicate a **Terraform Cloud-style plan/approve/apply workflow** entirely within GitHub Actions, using AWS OIDC authentication — no static credentials required.

## Overview

[Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) provides a managed workflow where:

- Pull requests trigger a speculative plan, visible in the PR
- Merges to the default branch trigger a plan, pause for manual approval, then apply
- State is stored remotely and locked during operations

### OIDC in Terraform Cloud Workspaces

Terraform Cloud supports [Dynamic Provider Credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials), which eliminates the need to store static cloud credentials in workspace variables. Instead, TFC acts as an OIDC identity provider and exchanges short-lived tokens for temporary AWS credentials at runtime — scoped to the duration of each plan or apply operation. This is straightforward to enable through simple workspace variable configuration, with no changes required to Terraform code.

**This repository replicates that same credential model natively within GitHub Actions**, with GitHub itself acting as the OIDC identity provider in place of HCP.

This repository achieves the same workflow natively in GitHub Actions by combining:

- **GitHub OIDC** for short-lived, dynamic AWS credentials (no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` stored as secrets)
- **S3** for both Terraform remote state and ephemeral plan file storage between jobs
- **GitHub environment protection rules** for the manual approval gate
- **`terraform plan -detailed-exitcode`** to skip the approval and apply stages when there are no infrastructure changes

---

## How It Works

### Authentication: GitHub OIDC → AWS

Each workflow job requests a short-lived OIDC token from GitHub and exchanges it for temporary AWS credentials by assuming an IAM role. The credentials exist only for the duration of the job and are never stored anywhere.

This requires:
1. An OIDC identity provider configured in AWS IAM for GitHub Actions
2. An IAM role with a trust policy that restricts assumption to this repository
3. The IAM role ARN stored as a GitHub Actions repository variable (`AWS_ROLE_ARN`)

The workflow declares `permissions: id-token: write` to allow GitHub to issue the OIDC token.

### State: S3 Backend

Terraform state is stored in an S3 backend, configured in `terraform/backend.tf`. The role assumed via OIDC has direct S3 permissions on the backend bucket, so the backend uses those ambient credentials. The same credentials are used by the Terraform AWS provider to manage resources.

### Plan File: S3 Handoff Between Jobs

Each GitHub Actions job runs on a **separate, ephemeral runner** — there is no shared filesystem between jobs. To pass the plan file from the plan job to the apply job without using GitHub Artifacts (which can contain sensitive data and accumulate over time), the plan file is uploaded to a dedicated prefix in the S3 backend bucket using `aws s3 cp`, keyed by the workflow run ID:

```
s3://<backend-bucket>/plan-files/run-<run_id>.tfplan
```

The run ID is stable and unique per workflow run, so both jobs can independently derive the correct S3 key. The plan file is deleted from S3 immediately after apply (or on failure), so no plan files accumulate.

### Workflow Stages

```
Any trigger
         │
         ▼
  ┌─────────────────┐
  │ validate-config │  Reads repository variables, validates and resolves
  └────────┬────────┘  role ARN configuration. Fails before any other action
           │           if configuration is invalid.
           ▼
  ┌─────────────────┐
  │ terraform-plan  │  Authenticates to AWS, runs terraform init and plan.
  └────────┬────────┘  On PRs: plan output to log only.
           │           On main: plan file written and uploaded to S3.
           │           If no changes: approval and apply are skipped.
           │ (main only, has_changes == true)
           ▼
  ┌─────────────────┐
  │    approval     │  Pauses for manual review via the GitHub Actions UI.
  └────────┬────────┘  Reviewers configured under Settings → Environments.
           │ approved
           ▼
  ┌─────────────────┐
  │ terraform-apply │  Downloads plan from S3, applies it, deletes plan file.
  └─────────────────┘
```

**On pull requests**, only `validate-config` and `terraform-plan` run. The plan output is visible in the job log, no file is written or uploaded.

**On push to main (or `workflow_dispatch`)**, the full pipeline runs. If the plan detects no changes, the approval and apply stages are skipped automatically.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml       # The CI/CD pipeline
└── terraform/
    ├── backend.tf              # S3 remote state configuration
    ├── providers.tf            # Terraform and provider version constraints
    ├── bucket.tf               # Example S3 bucket resource
    └── object.tf               # Example S3 object using a static timestamp
```

---

## Prerequisites

### 1. AWS OIDC Identity Provider

In your AWS account, create an OIDC identity provider:

- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`

This only needs to be done once per AWS account.

### 2. IAM Role

Create an IAM role with a trust policy that allows GitHub Actions to assume it. Scope the trust to your specific repository to prevent other GitHub repositories from assuming the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<your-org>/<your-repo>:*"
        }
      }
    }
  ]
}
```

This is the **OIDC role** — it is the single operational role used by Terraform. It needs read/write access to the S3 backend bucket (for state and ephemeral plan files) and permissions to manage whatever AWS resources your Terraform configuration defines. See [Role ARN Configuration](#role-arn-configuration) for how to configure plan-only and plan+apply variants of this role.

### 3. S3 Backend Bucket

An S3 bucket to store both Terraform state and ephemeral plan files. Versioning is recommended on this bucket to allow state recovery.

### 4. GitHub Repository Configuration

#### Repository Variables

Go to **Settings → Secrets and variables → Actions → Variables**. Role ARNs are not credentials, so repository variables (not secrets) are the correct place for them.

The minimum required variable is:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN` | The IAM role assumed via OIDC. Used for state access, plan file storage, and resource management. |

See [Role ARN Configuration](#role-arn-configuration) below for how to configure separate plan and apply roles.

#### Production Environment

Go to **Settings → Environments** and create an environment named `production`. Under **Deployment protection rules**, enable **Required reviewers** and add the users or teams who should be able to approve deployments.

When a push to `main` triggers the workflow, the pipeline will pause at the approval stage and notify the configured reviewers.

---

## Workflow Configuration Reference

### Workflow `env` Variables

These are set at the top of `.github/workflows/terraform.yml`:

| Variable | Description |
|---|---|
| `AWS_REGION` | The AWS region to authenticate against |
| `TF_VERSION` | The Terraform CLI version to install |
| `PLAN_BUCKET` | S3 bucket used for ephemeral plan file storage |
| `PLAN_KEY` | S3 key for the plan file — scoped to the workflow run ID automatically |

---

## Role ARN Configuration

All values are set as **repository variables** under Settings → Secrets and variables → Actions → Variables.

The workflow supports a single IAM role used for all stages, or separate roles for the plan and apply stages. Both modes are configured through the same `AWS_ROLE_ARN` variable family.

**Simple** — use the same role for both plan and apply:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role assumed via OIDC for all stages |

**Stage-specific** — use a read-only role for plan and a read/write role for apply. Both must be set together; setting only one is an error:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN_PLAN` | Role assumed during the plan stage (read-only permissions recommended) |
| `AWS_ROLE_ARN_APPLY` | Role assumed during the apply stage (read/write permissions required) |

For example:

```
AWS_ROLE_ARN_PLAN  = arn:aws:iam::123456789012:role/tf-plan-ro
AWS_ROLE_ARN_APPLY = arn:aws:iam::123456789012:role/tf-apply-rw
```

Each role needs:
- S3 permissions on the backend bucket (read for plan, read/write for apply)
- Permissions to manage the AWS resources defined in your Terraform configuration

If the configuration is invalid (e.g. `_PLAN` set without `_APPLY`, or no role configured at all), the `validate-config` job fails with an error annotation before any AWS or Terraform action runs.

---

## Adapting This for Your Own Use

1. Update `terraform/backend.tf` with your own S3 bucket name, state key path, and region
2. Update `AWS_REGION`, `TF_VERSION`, and `PLAN_BUCKET` in the workflow `env` block to match
3. Replace the resources in `terraform/bucket.tf` and `terraform/object.tf` with your own infrastructure
4. Follow the prerequisites above to configure the AWS OIDC provider, IAM roles, and GitHub environment
5. Set repository variables for `AWS_ROLE_ARN` (or the stage-specific `AWS_ROLE_ARN_PLAN`/`AWS_ROLE_ARN_APPLY` variants — see [Role ARN Configuration](#role-arn-configuration))

No other changes to the workflow are required.

---

## Security Notes

- **No static credentials** are stored anywhere. The OIDC token exchange produces short-lived session credentials that expire when the job ends.
- **Plan files are ephemeral.** They are uploaded to S3 only for the duration between the plan and apply jobs, then deleted immediately — even if the apply fails (`if: always()`).
- **Plan files are not stored as GitHub Artifacts**, which avoids both retention accumulation and the risk of sensitive plan content being accessible through the GitHub UI.
- **The trust policy is scoped to a single repository.** The `sub` condition in the IAM trust policy ensures that only workflows from this specific repository can assume the OIDC role.
- **The approval gate uses a GitHub-managed environment**, meaning the reviewer list and bypass rules are controlled in GitHub settings and audited in the deployment history.
