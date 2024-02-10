# Media Bucket for Video Uploads - used by the chunkProcessor, abandonedStream, API, and BatchProcessor.
# It lives here with the lambdas because it's easier to set up access permissions here for the lambdas
resource "random_pet" "matrix_name" {
  prefix = "${local.name.prefix}-matrix"
  length = 2
}

resource "aws_s3_bucket" "matrix_uploads" {
  bucket = "${local.name.prefix}-matrix"
  # bucket = "${random_pet.matrix_name.id}"
  force_destroy = false

  tags = {
    Name        = "Matrix File Upload Trigger Bucket"
    Environment = "${var.stage}"
  }
}

resource "aws_s3_bucket_public_access_block" "matrix_uploads" {
  bucket = aws_s3_bucket.matrix_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "matrix_uploads" {
  bucket = aws_s3_bucket.matrix_uploads.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "matrix_uploads" {
  depends_on = [
    aws_s3_bucket_public_access_block.matrix_uploads,
    aws_s3_bucket_ownership_controls.matrix_uploads
  ]

  bucket = aws_s3_bucket.matrix_uploads.id
  acl    = "private"
}

resource "aws_s3_bucket_notification" "matrix_uploads" {
  bucket = aws_s3_bucket.matrix_uploads.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestor.arn
    events              = ["s3:ObjectCreated:*"] 
    # events              = ["s3:ObjectCreated:Put"]
    filter_prefix = "uploads/"
    filter_suffix = ".csv"
  }

  depends_on   = [aws_lambda_function.ingestor]
}
resource "aws_lambda_permission" "matrix_uploads" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.matrix_uploads.arn
}

# CORS: Allowed domains for uploading from web webrowser
# NOTE: Additional hosts/ips would need to be added if any uploads are done programatically
locals {
  matrix_client_urls = var.stage == "stage" ? ["http://localhost:3000", "http://localhost:3001", "https://stage.${var.domain_name}"] : ["http://localhost:3000", "https://${var.domain_name}", "https://www.${var.domain_name}"]
}

resource "aws_s3_bucket_cors_configuration" "matrix_client_uploads" {
  bucket = aws_s3_bucket.matrix_uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = local.matrix_client_urls
    expose_headers  = ["ETag"]
    # max_age_seconds = 3000
  }

}

# resource "aws_iam_policy" "s3_policy" {
#   name        = "${random_pet.matrix_name.id}-policy"
#   description = "${random_pet.matrix_name.id}-policy"
  
#   policy = templatefile("${path.module}/policies/s3-media-bucket-policy.json", { src_bucket_arn: aws_s3_bucket.matrix_uploads.arn }) // , labmda-role-arn: aws_lambda_function.
# }

# resource "aws_s3_bucket_policy" "s3_policy" {
#   role = aws_s3_bucket.matrix_uploads.id
#   policy_arn = aws_iam_policy.s3_policy.arn
# }