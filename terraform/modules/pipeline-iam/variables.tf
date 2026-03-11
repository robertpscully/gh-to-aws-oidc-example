variable "github_org" {
  type        = string
  description = "GitHub organisation or user that owns the repository (e.g. 'my-org')"
}

variable "repo_name" {
  type        = string
  description = "Repository name without the org prefix (e.g. 'my-repo')"
}

variable "workspace_id" {
  type        = string
  description = "Workspace identifier for state path isolation. Allows multiple independent deployments from the same repository (e.g. 'default', 'staging', 'prod')."
  default     = "default"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the GitHub Actions OIDC identity provider configured in this AWS account"
}

variable "role_name_prefix" {
  type        = string
  description = "Prefix for all IAM role names created by this module. Simple mode produces '<prefix>-terraform'. Stage-specific mode produces '<prefix>-plan' and '<prefix>-apply'."
}

variable "state_bucket" {
  type        = string
  description = "Name of the shared S3 bucket used for Terraform state and ephemeral plan file storage"
}

variable "create_stage_specific_roles" {
  type        = bool
  description = "If true, creates separate read-only (plan) and read-write (apply) roles. If false, creates a single role covering both stages."
  default     = false
}

variable "resource_policy_document" {
  type        = string
  default     = null
  description = "JSON IAM policy document granting the pipeline's role(s) access to the AWS resources it manages. When provided, a new managed policy is created and attached. When null, no resource-access policy is created."
}

variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "ARNs of pre-existing IAM managed policies to attach to the pipeline role(s). Use to attach policies that were created outside this module, in addition to or instead of resource_policy_document."
}
