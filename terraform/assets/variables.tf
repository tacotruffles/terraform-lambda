variable "lambda_memory_size" {
  description = "Lambda memory allocation"
  type = number
  default = 2048 # MB
}

output "lambda-exec-id" {
  value = data.terraform_remote_state.networking.outputs.api_lambda_exec.id
}

variable matrixIngestor_code_path {
  description = "Where the matrixIngestor code base lives so we can build and deploy it"
  type = string
  default = "matrixIngestor"
}

variable messageHandler_code_path {
  description = "Where the messageHandler code base lives so we can build and deploy it"
  type = string
  default = "messageHandler"
}

# Ingest .env file as sensitve values to avoid flashing in logs, etc.
# GitHub Actions will generate .env from {{ $secrets.LAMBDA_<STAGE>_DOTENV }}
# Ignores commented lines and the `AWS_PROFILE` environment variable which is only needed locally
locals {
  env_matrixIngestor = { for tuple in regexall("(.*?)=(.*)", file("${path.module}/../../${var.matrixIngestor_code_path}/.env")) : tuple[0] => tuple[1] if (tuple[0] != "AWS_PROFILE")  }
}

locals {
  env_messageHandler = { for tuple in regexall("(.*?)=(.*)", file("${path.module}/../../${var.messageHandler_code_path}/.env")) : tuple[0] => tuple[1] if (tuple[0] != "AWS_PROFILE")  }
}

# Generate project-based prefix string for user-friendly asset names
locals {
  name = {
    prefix = "${var.prefix}-${var.stage}"
  }
}

variable "stage" {
  description = "CI/CD pipeline stage"
  type = string
  default = "stage"
}

variable "prefix" {
  description = "Acronym for your project"
  type = string
}
variable "aws_region" {
  description = "AWS region for deployment"
  type = string
}

variable "aws_profile" {
  description = "AWS CLI Profile name"
  type = string
}

variable "domain_name" {
  description = "Registered Domain Name for S3 Static Site/CloudFront/ACM"
  type = string
}

variable "tf_state_bucket" {
  description = "Terraform Backend: S3 bucket"
  type = string
}

variable "tf_state_key" {
  description = "Terraform Backend: S3 key"
  type = string
}

# TBD - A lock table is only needed if more than one path is possible for building infrastructure.
# And since lock tables are handled by DocumentDB only...a very expensive way to have a lock table
# with one field. Additionally,  GitHub Actions are handling builds sequentially so it's not an issue yet.
# variable "tf_state_table" {
#   description = "Terraform Backend: S3 state table"
#   type = string
# }