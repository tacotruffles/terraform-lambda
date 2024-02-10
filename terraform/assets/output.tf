# FROM: Networking State File
output "whitelist_ip" {
  value = data.terraform_remote_state.networking.outputs.whitelist_ip
}


output "s3_triggered_lambda" {
  value = aws_lambda_function.ingestor.id
}

output "s3_upload_bucket" {
  value = aws_s3_bucket.uploads.id
}

output "s3_upload_arn" {
  value = aws_s3_bucket.uploads.arn
}

output "s3_matrix_upload_bucket" {
  value = aws_s3_bucket.matrix_uploads.id
}

output "matrix_ingestor_arn" {
  value = aws_lambda_function.ingestor.arn
}
