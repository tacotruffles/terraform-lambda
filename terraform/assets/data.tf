# Pull in remote state file for AWS Networking
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "${var.prefix}-global-tf-states"
    key = "${var.prefix}-global-networking.tf"
    region = var.aws_region
    profile = var.aws_profile
  }
}
