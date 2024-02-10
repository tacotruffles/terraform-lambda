terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~>2.2.0"
    }
  }

  required_version = "~> 1.0"

  backend "s3" {
    bucket = "${var.tf_state_bucket}" # variables can't be used here.
    key = "${var.tf_state_key}"
    region = "${var.aws_region}" # variables can't be used here.
    profile = "${var.aws_profile}" # variables can't be used here.
  }
}

provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}