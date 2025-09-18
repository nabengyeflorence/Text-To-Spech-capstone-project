terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.5.0"
}


#Frontend bucket (static site)
resource "aws_s3_bucket" "frontend" {
  bucket = var.frontend_bucket_name
  force_destroy = true
}
#website configuration
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "TTS.html"
  }

  error_document {
    key = "TTS.html"
  }
}
# Public access block (allow website hosting to work)
resource "aws_s3_bucket_public_access_block" "frontend_block" {
  bucket = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Bucket policy for public-read access
#resource "aws_s3_bucket_policy" "frontend_bucket__policy" {
  #bucket = aws_s3_bucket.frontend.id
  #policy = jsonencode({
    #Version = "2012-10-17"
    #Statement = [
      #{
        #Effect = "Allow"
        #Principal = "*"
        #Action   = "s3:GetObject"
        #Resource = "${aws_s3_bucket.frontend.arn}/*"
      #}
    #]
  #})
#}


# Audio bucket 
resource "aws_s3_bucket" "audio_bucket" {
  bucket        = var.audio_bucket_name
  force_destroy = true
}

# Lifecycle configuration (replaces lifecycle_rule)
resource "aws_s3_bucket_lifecycle_configuration" "audio_bucket" {
  bucket = aws_s3_bucket.audio_bucket.id

  rule {
    id     = "expire-audio"
    status = "Enabled"

    expiration {
      days = var.audio_expire_days
    }
  }
}


# IAM role and policy for Lambda
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.prefix}-tts-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid     = "AllowPolly"
    actions = ["polly:SynthesizeSpeech", "polly:SynthesizeSpeechStream"]
    resources = ["*"]
  }

  statement {
    sid = "AllowS3Audio"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.audio_bucket.arn}/*"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.prefix}-tts-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ---------- Lambda function (zip must be created before terraform apply)
resource "aws_lambda_function" "tts_function" {
  filename         = var.lambda_zip_path
  function_name    = "${var.prefix}-tts-synthesize"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_polly.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  timeout          = 30
  memory_size      = 512

  environment {
    variables = {
      S3_BUCKET            = aws_s3_bucket.audio_bucket.bucket
      AUDIO_EXPIRE_SECONDS = tostring(var.audio_presign_ttl_seconds)
    }
  }
}

# ---------- API Gateway v2 (HTTP API)
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["OPTIONS", "POST"]
    allow_headers = ["Content-Type"]
    expose_headers = []
    max_age = 300
  }
}




resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                  = aws_apigatewayv2_api.http_api.id
  integration_type        = "AWS_PROXY"
  integration_uri         = aws_lambda_function.tts_function.invoke_arn
  payload_format_version  = "2.0"
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /synthesize"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}


resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tts_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
