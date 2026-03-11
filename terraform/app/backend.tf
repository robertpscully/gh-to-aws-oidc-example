terraform {
  backend "s3" {
    # Bucket created by terraform/devops-infra. After applying devops-infra,
    # retrieve the name from its output:
    #
    #   cd terraform/devops-infra && terraform output shared_state_bucket
    #
    # Then set the value here.
    bucket = "REPLACE_WITH_DEVOPS_INFRA_SHARED_STATE_BUCKET"
    region = "eu-west-2"

    # The state key is not set here. It is injected at init time by the workflow
    # using -backend-config so that each workspace gets its own isolated state:
    #
    #   terraform init -backend-config="key=state/<org>/<repo>/<workspace>/terraform.tfstate"
    #
    # The workflow derives this automatically from github.repository and the
    # workspace_id input. See .github/workflows/terraform.yml.
  }
}
