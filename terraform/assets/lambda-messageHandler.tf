# A Lambda API pattern that executes a zipped NodeJS function 
# from an S3 bucket to get around the 50MB direct upload file size limt

### 1. Setup S3 Bucket for Zipped API code
# Set up random bucket naming
resource "random_pet" "lambda_name_message_handler" {
  prefix = "${local.name.prefix}-message-handler"
  length = 1
}

# Define S3 Bucket
resource "aws_s3_bucket" "message_handler_lambda_bucket" {
  bucket        = random_pet.lambda_name_message_handler.id
  force_destroy = true
}

# Block Public Access to S3 Lambda Bucket
resource "aws_s3_bucket_public_access_block" "message_handler_access_policy" {
  bucket = aws_s3_bucket.message_handler_lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

### 2. Set up Lambda access via IAM
# Define a policy to allow executing lambdas
resource "aws_iam_role" "message_handler_lambda_exec" {
  name = "${random_pet.lambda_name_message_handler.id}-lambda-exec"

  assume_role_policy = templatefile("${path.module}/policies/lambda-execution-policy.json", {})
}

# Attach this policy to a basic lambda execution role
resource "aws_iam_role_policy_attachment" "as_lambda_policy_exec" {
  role       = aws_iam_role.message_handler_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC policy to same exectution role for Lambdas for documentDB / NAT Gateway permissions
resource "aws_iam_role_policy_attachment" "as_lambda_policy_vpc" {
  role       = aws_iam_role.message_handler_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


### 3. Setup Lambda Function
resource "aws_lambda_function" "message_handler" {
  function_name = "${random_pet.lambda_name_message_handler.id}"
  description = "S3 triggered lambda that retrieves metadata for the object that has been updated, saves it, and creates an SQS msg"

  s3_bucket = aws_s3_bucket.message_handler_lambda_bucket.id
  s3_key    = aws_s3_object.message_handler_code.key

  runtime = "python3.11"
  # handler = "main.handler"
  # handler = "db_function.handler"
  handler = "lambda_function.lambda_handler"

  source_code_hash = data.archive_file.lambda_message_handler_code.output_base64sha256
  # layers = []

  role = aws_iam_role.message_handler_lambda_exec.arn

  timeout = 60 #seconds
  memory_size = 2048 #MB
  # ephemeral_storage {
  #   size = 8192 #MB
  # }

  # To prevent feedback loops on video processing - uncommment if needed
  # reserved_concurrent_executions = 75

  vpc_config {
    subnet_ids = [data.terraform_remote_state.networking.outputs.private_subnet_id]
    security_group_ids = [data.terraform_remote_state.networking.outputs.vpc_security_group_id]
  }

  # Pattern for ingesting .env file with internal Terraform Files
  dynamic "environment" {
    for_each = local.env_messageHandler != null ? local.env_messageHandler[*] : []
    
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

resource "aws_iam_policy" "message_handler_s3_policy" {
  name        = "${random_pet.lambda_name_message_handler.id}-s3-policy"
  description = "${random_pet.lambda_name_message_handler.id}-s3-policy"
  
  policy = templatefile("${path.module}/policies/lambda-s3-media-bucket-policy.json", { src_bucket_arn: aws_s3_bucket.uploads.arn })
}

# Attach both the API execution role for VPC/NAT access and S3 uploads bucket access
resource "aws_iam_role_policy_attachment" "message_handler_s3_iam_policy" {
 role = aws_iam_role.message_handler_lambda_exec.id
 policy_arn = "${aws_iam_policy.message_handler_s3_policy.arn}"
}

resource "aws_iam_policy" "message_handler_sqs_policy" {
  name        = "${random_pet.lambda_name_message_handler.id}-sqs-policy"
  description = "${random_pet.lambda_name_message_handler.id}-sqs-policy"
  
  policy = templatefile("${path.module}/policies/lambda-sqs-policy.json", {}) // FULL ACCESS for now , { src_bucket_arn: aws_s3_bucket.uploads.arn }
}

# Attach SQS Queue policy for Lambda
resource "aws_iam_role_policy_attachment" "message_handler_sqs_iam_policy" {
 role = aws_iam_role.message_handler_lambda_exec.id
 policy_arn = "${aws_iam_policy.message_handler_sqs_policy.arn}"
}

# ZIP Lambda Function Code
data "archive_file" "lambda_message_handler_code" {
  type = "zip"

  source_dir  = "${path.module}/../../build/${var.messageHandler_code_path}"
  output_path = "${path.module}/../../build/${random_pet.lambda_name_message_handler.id}.zip"
}

# Upload code artifact to S3 bucket
resource "aws_s3_object" "message_handler_code" {
  bucket = aws_s3_bucket.message_handler_lambda_bucket.id

  key    = "${random_pet.lambda_name_message_handler.id}.zip"
  source = data.archive_file.lambda_message_handler_code.output_path

  # Use source_hash instead as there's a 16MB limit 
  # where uploads will become multi-part zips on S3 with 
  # using etag as the trigger
  # etag = filemd5(data.archive_file.lambda_message_handler_code.output_path)
  source_hash = filemd5(data.archive_file.lambda_message_handler_code.output_path)
}

# Logging for lambda console.log statements
resource "aws_cloudwatch_log_group" "lambda_message_handler" {
  name = "/aws/lambda/${aws_lambda_function.message_handler.function_name}"

  retention_in_days = 14 # 14 or 30 is recommended depending on CI/CD env
}