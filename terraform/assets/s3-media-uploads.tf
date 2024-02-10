# Media Bucket for Video Uploads - used by the chunkProcessor, abandonedStream, API, and BatchProcessor.
# It lives here with the lambdas because it's easier to set up access permissions here for the lambdas
resource "random_pet" "uploads_name" {
  prefix = "${local.name.prefix}-media"
  length = 2
}

resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name.prefix}-upload" //"${random_pet.uploads_name.id}"
  force_destroy = false

  tags = {
    Name        = "Upload Trigger Bucket"
    Environment = "${var.stage}"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "uploads" {
  depends_on = [
    aws_s3_bucket_public_access_block.uploads,
    aws_s3_bucket_ownership_controls.uploads
  ]

  bucket = aws_s3_bucket.uploads.id
  acl    = "private"
}

# S3 Trigger
resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.message_handler.arn # "arn:aws:lambda:us-east-1:765228178068:function:aiai-stage-process-trigger-messages"
    events              = ["s3:ObjectCreated:*"] 
    # events              = ["s3:ObjectCreated:Put"]
    filter_prefix = "uploads/"
    filter_suffix = ".mp4"
  }

  depends_on   = [aws_lambda_function.message_handler]
}

resource "aws_lambda_permission" "uploads" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name =  aws_lambda_function.message_handler.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

# TBD: forward www with CNAME on prod
locals {
  message_handler_client_urls = var.stage == "stage" ? ["http://localhost:3000", "http://localhost:3001", "https://stage.${var.domain_name}"] : ["http://localhost:3000", "http://localhost:3001", "https://${var.domain_name}", "https://www.${var.domain_name}"]
}

resource "aws_s3_bucket_cors_configuration" "client_uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = local.message_handler_client_urls
    expose_headers  = ["ETag"]
    # max_age_seconds = 3000
  }

}
