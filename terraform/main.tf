# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

locals {
  aliases = var.use_custom_domain && var.root_domain != "" ? [
    var.root_domain,
    "www.${var.root_domain}"
  ] : []

  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

############################################
# S3 bucket for conversation memory
############################################
resource "aws_s3_bucket" "memory" {
  bucket = "${local.name_prefix}-memory-${data.aws_caller_identity.current.account_id}"git 
  force_destroy = true
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "memory" {
  bucket = aws_s3_bucket.memory.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "memory" {
  bucket = aws_s3_bucket.memory.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

############################################
# S3 bucket for frontend static website
############################################
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

############################################
# IAM role for primary (FastAPI) Lambda
############################################
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

############################################
# Primary Lambda function (FastAPI via Mangum)
############################################
resource "aws_lambda_function" "api" {
  filename         = "${path.module}/../backend/lambda-deployment.zip"
  function_name    = "${local.name_prefix}-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_handler.handler"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda-deployment.zip")
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = var.lambda_timeout
  memory_size      = 1024
  tags             = local.common_tags

  environment {
    variables = {
      # Make region explicit for boto3 client selection
      DEFAULT_AWS_REGION = var.aws_region

      CORS_ORIGINS     = var.use_custom_domain ? "https://${var.root_domain},https://www.${var.root_domain}" : "https://${aws_cloudfront_distribution.main.domain_name}"
      S3_BUCKET        = aws_s3_bucket.memory.id
      USE_S3           = "true"
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  depends_on = [aws_cloudfront_distribution.main]
}

############################################
# API Gateway HTTP API (non-streaming)
############################################
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api-gateway"
  protocol_type = "HTTP"
  tags          = local.common_tags

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_origins     = ["*"]
    max_age           = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

############################################
# Streaming stack: REST API + streaming Lambda
############################################

# IAM role for streaming Lambda (Node.js)
resource "aws_iam_role" "stream_lambda_role" {
  name = "${local.name_prefix}-stream-lambda-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "stream_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.stream_lambda_role.name
}

resource "aws_iam_role_policy_attachment" "stream_lambda_bedrock" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  role       = aws_iam_role.stream_lambda_role.name
}

# Streaming Lambda (Node.js zip you will build)
resource "aws_lambda_function" "stream" {
  filename         = "${path.module}/../backend/stream-lambda.zip"
  function_name    = "${local.name_prefix}-stream"
  role             = aws_iam_role.stream_lambda_role.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/../backend/stream-lambda.zip")
  runtime          = "nodejs20.x"
  architectures    = ["x86_64"]
  timeout          = 120
  memory_size      = 1024
  tags             = local.common_tags

  environment {
    variables = {
      #AWS_REGION       = var.aws_region
      BEDROCK_MODEL_ID = var.bedrock_model_id
      
      # Optional: if you want to be explicit, use a non-reserved name:
      BEDROCK_REGION   = var.aws_region
    }
  }
}

# REST API (v1) with streaming enabled integration
resource "aws_api_gateway_rest_api" "stream" {
  name        = "${local.name_prefix}-stream-rest-api"
  description = "REST API only for /chat/stream (response streaming)"
  tags        = local.common_tags

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# /chat
resource "aws_api_gateway_resource" "stream_chat" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  parent_id   = aws_api_gateway_rest_api.stream.root_resource_id
  path_part   = "chat"
}

# /chat/stream
resource "aws_api_gateway_resource" "stream_chat_stream" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  parent_id   = aws_api_gateway_resource.stream_chat.id
  path_part   = "stream"
}

# POST /chat/stream
resource "aws_api_gateway_method" "stream_post" {
  rest_api_id   = aws_api_gateway_rest_api.stream.id
  resource_id   = aws_api_gateway_resource.stream_chat_stream.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda proxy integration with response streaming (STREAM) and special URI
resource "aws_api_gateway_integration" "stream_post" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  resource_id = aws_api_gateway_resource.stream_chat_stream.id
  http_method = aws_api_gateway_method.stream_post.http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"

  # IMPORTANT: response streaming requires "response-streaming-invocations"
  # and response_transfer_mode = STREAM
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2021-11-15/functions/${aws_lambda_function.stream.arn}/response-streaming-invocations"

  response_transfer_mode = "STREAM"
  timeout_milliseconds   = 90000
}

# CORS preflight for /chat/stream
resource "aws_api_gateway_method" "stream_options" {
  rest_api_id   = aws_api_gateway_rest_api.stream.id
  resource_id   = aws_api_gateway_resource.stream_chat_stream.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "stream_options" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  resource_id = aws_api_gateway_resource.stream_chat_stream.id
  http_method = aws_api_gateway_method.stream_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "stream_options_200" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  resource_id = aws_api_gateway_resource.stream_chat_stream.id
  http_method = aws_api_gateway_method.stream_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "stream_options_200" {
  rest_api_id = aws_api_gateway_rest_api.stream.id
  resource_id = aws_api_gateway_resource.stream_chat_stream.id
  http_method = aws_api_gateway_method.stream_options.http_method
  status_code = aws_api_gateway_method_response.stream_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.stream_options]
}

# Deployment + stage
resource "aws_api_gateway_deployment" "stream" {
  rest_api_id = aws_api_gateway_rest_api.stream.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_method.stream_post.id,
      aws_api_gateway_integration.stream_post.id,
      aws_api_gateway_method.stream_options.id,
      aws_api_gateway_integration.stream_options.id,
      aws_api_gateway_integration_response.stream_options_200.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.stream_post,
    aws_api_gateway_integration_response.stream_options_200
  ]
}

resource "aws_api_gateway_stage" "stream" {
  rest_api_id   = aws_api_gateway_rest_api.stream.id
  deployment_id = aws_api_gateway_deployment.stream.id
  stage_name    = "prod"
  tags          = local.common_tags
}

# Allow REST API to invoke the streaming Lambda
resource "aws_lambda_permission" "stream_api_gw" {
  statement_id  = "AllowExecutionFromStreamRestApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stream.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.stream.execution_arn}/*/*"
}

############################################
# CloudFront distribution (unchanged)
############################################
resource "aws_cloudfront_distribution" "main" {
  aliases = local.aliases

  viewer_certificate {
    acm_certificate_arn            = var.use_custom_domain ? aws_acm_certificate.site[0].arn : null
    cloudfront_default_certificate = var.use_custom_domain ? false : true
    ssl_support_method             = var.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  tags                = local.common_tags

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}

############################################
# Optional: Custom domain configuration (unchanged)
############################################
data "aws_route53_zone" "root" {
  count        = var.use_custom_domain ? 1 : 0
  name         = var.root_domain
  private_zone = false
}

resource "aws_acm_certificate" "site" {
  count                     = var.use_custom_domain ? 1 : 0
  provider                  = aws.us_east_1
  domain_name               = var.root_domain
  subject_alternative_names = ["www.${var.root_domain}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = local.common_tags
}

resource "aws_route53_record" "site_validation" {
  for_each = var.use_custom_domain ? {
    for dvo in aws_acm_certificate.site[0].domain_validation_options :
    dvo.domain_name => dvo
  } : {}

  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 300
  records = [each.value.resource_record_value]
}

resource "aws_acm_certificate_validation" "site" {
  count           = var.use_custom_domain ? 1 : 0
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [
    for r in aws_route53_record.site_validation : r.fqdn
  ]
}

resource "aws_route53_record" "alias_root" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_root_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_www" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_www_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
