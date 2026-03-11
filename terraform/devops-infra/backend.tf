terraform {
  backend "s3" {
    bucket = "robertscully-terraform-s3-backend"
    key    = "nonprod/devops-infra/terraform.tfstate"
    region = "eu-west-2"
  }
}
