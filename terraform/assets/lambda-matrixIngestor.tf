# A Lambda API pattern that executes a zipped NodeJS function 
# from an S3 bucket to get around the 50MB direct upload file size limt

### 1. Setup S3 Bucket for Zipped API code
# Set up random bucket naming
resource "random_pet" "lambda_name" {
  prefix = "${local.name.prefix}-matrix-ingestor"
  length = 2
}

# Define S3 Bucket
resource "aws_s3_bucket" "ingestor_lambda_bucket" {
  bucket        = random_pet.lambda_name.id
  force_destroy = true
}

# Block Public Access to S3 Lambda Bucket
resource "aws_s3_bucket_public_access_block" "ingestor_access_policy" {
  bucket = aws_s3_bucket.ingestor_lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

### 2. Set up Lambda access via IAM
# Define a policy to allow executing lambdas
resource "aws_iam_role" "ingestor_lambda_exec" {
  name = "${random_pet.lambda_name.id}-lambda-exec"

  assume_role_policy = templatefile("${path.module}/policies/lambda-execution-policy.json", {})
}

# Attach this policy to a basic lambda execution role for API GATEWAY
resource "aws_iam_role_policy_attachment" "ingestor_lambda_policy_api_gw" {
  role       = aws_iam_role.ingestor_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC policy to same exectution role for Lambdas internet access inside VPC/NAT Gateway
resource "aws_iam_role_policy_attachment" "ingestor_lambda_policy_vpc" {
  role       = aws_iam_role.ingestor_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


### 3. Setup Lambda Function
resource "aws_lambda_function" "ingestor" {
  function_name = "${random_pet.lambda_name.id}"
  description = "Lambda: Matrix File Ingestor Triggerd by S3 upload"

  s3_bucket = aws_s3_bucket.ingestor_lambda_bucket.id
  s3_key    = aws_s3_object.lambda_code.key

  runtime = "python3.11"
  # handler = "main.handler"
  handler = "lambda_function.lambda_handler"
  
  source_code_hash = data.archive_file.lambda_ingestor_code.output_base64sha256
  layers = ["arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python311:4"]

  # Passed in from split state file: networking.tf
  # role = data.terraform_remote_state.networking.outputs.api_lambda_exec.arn
  role = aws_iam_role.ingestor_lambda_exec.arn

  timeout = 60 #seconds
  memory_size = 2048 #MB
  # ephemeral_storage {
  #   size = 8192 #MB
  # }

  # To prevent feedback loops on video processing - uncommment if needed
  # reserved_concurrent_executions = 75

  # DONT NEED:
  vpc_config {
    subnet_ids = [data.terraform_remote_state.networking.outputs.private_subnet_id]
    security_group_ids = [data.terraform_remote_state.networking.outputs.vpc_security_group_id]
  }

  # Pattern for ingesting .env file with internal Terraform Files
  dynamic "environment" {
    for_each = local.env_matrixIngestor != null ? local.env_matrixIngestor[*] : []
    
    content {
      variables = merge({ S3_BUCKET = aws_s3_bucket.uploads.id }, environment.value)
    }
  }

  # Pattern for setting Lambda environment variables statically
  # environment {
  #   variables = {
  #     # Environment Settings
  #     S3_BUCKET = aws_s3_bucket.uploads.id
  #   }
  # }
}

resource "aws_iam_policy" "matrix_lambda_policy" {
  name        = "${random_pet.lambda_name.id}-policy"
  description = "${random_pet.lambda_name.id}-policy"
  
  policy = templatefile("${path.module}/policies/lambda-s3-media-bucket-policy.json", { src_bucket_arn: aws_s3_bucket.matrix_uploads.arn })
}

# Attach both the API execution role for VPC/NAT access and S3 uploads bucket access
resource "aws_iam_role_policy_attachment" "matrix_lambda_iam_policy" {
 role = data.terraform_remote_state.networking.outputs.api_lambda_exec.id
 policy_arn = "${aws_iam_policy.matrix_lambda_policy.arn}"
}

# ZIP Dependencies - doesn't work because Terraform wants to nest files in parent folder
# ./tf.sh will handle this now
# data "archive_file" "layer" {
#   type        = "zip"
#   source_dir  = "${path.module}/../../build/${var.matrixIngestor_code_path}-layer"
#   output_path = "${path.module}/../../build/${var.matrixIngestor_code_path}-layer.zip" # 
#   # depends_on  = [null_resource.pip_install]
# }

# Related to above resource - no longer used.
# # Create Dependencies as a Layer
# resource "aws_lambda_layer_version" "lambda_ingestor_layer" {
#   layer_name          = "${var.matrixIngestor_code_path}-requirements"
#   filename            = data.archive_file.layer.output_path
#   source_code_hash    = data.archive_file.layer.output_base64sha256
#   compatible_runtimes = ["python3.9", "python3.8", "python3.7"]
# }

# ZIP Lambda Function Code
data "archive_file" "lambda_ingestor_code" {
  type = "zip"

  source_dir  = "${path.module}/../../build/${var.matrixIngestor_code_path}"
  output_path = "${path.module}/../../build/${random_pet.lambda_name.id}.zip"
}

# Upload code artifact to S3 bucket
resource "aws_s3_object" "lambda_code" {
  bucket = aws_s3_bucket.ingestor_lambda_bucket.id

  key    = "${random_pet.lambda_name.id}.zip"
  source = data.archive_file.lambda_ingestor_code.output_path

  # Use source_hash instead as there's a 16MB limit 
  # where uploads will become multi-part zips on S3 with 
  # using etag as the trigger
  # etag = filemd5(data.archive_file.lambda_ingestor_code.output_path)
  source_hash = filemd5(data.archive_file.lambda_ingestor_code.output_path)
}

# Logging for lambda console.log statements
resource "aws_cloudwatch_log_group" "lambda_ingestor" {
  name = "/aws/lambda/${aws_lambda_function.ingestor.function_name}"

  retention_in_days = 14 # 14 or 30 is recommended depending on CI/CD env
}