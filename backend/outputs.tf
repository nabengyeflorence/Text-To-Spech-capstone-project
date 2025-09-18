output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "frontend_site_url" {
  value = aws_s3_bucket.frontend.website_endpoint
}

output "audio_bucket" {
  value = aws_s3_bucket.audio_bucket.bucket
}
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

