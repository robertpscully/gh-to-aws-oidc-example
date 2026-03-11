variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "github_org" {
  type        = string
  description = "GitHub organisation or user that owns all registered repositories (e.g. 'my-org')"
}

variable "state_bucket_name" {
  type        = string
  description = "Name for the shared S3 bucket that stores Terraform state and ephemeral plan files for all registered pipelines"
}
