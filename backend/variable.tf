variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "prefix" {
  type = string
  default = "demo"
}

variable "frontend_bucket_name" {
  type = string
}

variable "audio_bucket_name" {
  type = string
}

variable "audio_expire_days" {
  type    = number
  default = 7
}

variable "lambda_zip_path" {
  type    = string
  default = "../lambda/create_post.zip"
}

variable "audio_presign_ttl_seconds" {
  type    = number
  default = 3600
}
