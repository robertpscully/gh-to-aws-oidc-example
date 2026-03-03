terraform {
  backend "s3" {
    bucket = "robertscully-terraform-s3-backend"
    key = "nonprod/examples/gh-to-aws-oidc-example.tfstate"
    region = "eu-west-2"
  }
}