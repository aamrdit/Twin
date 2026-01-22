output "api_gateway_url" {
  description = "URL of the HTTP API Gateway (non-streaming)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "stream_api_url" {
  description = "URL of the REST API streaming endpoint (POST /chat/stream)"
  value       = "https://${aws_api_gateway_rest_api.stream.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.stream.stage_name}/chat/stream"
}

output "cloudfront_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_memory_bucket" {
  description = "Name of the S3 bucket for memory storage"
  value       = aws_s3_bucket.memory.id
}

output "lambda_function_name" {
  description = "Name of the primary Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "stream_lambda_function_name" {
  description = "Name of the streaming Lambda function"
  value       = aws_lambda_function.stream.function_name
}

output "custom_domain_url" {
  description = "Root URL of the production site"
  value       = var.use_custom_domain ? "https://${var.root_domain}" : ""
}
