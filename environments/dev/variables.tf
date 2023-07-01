variable "prefix" {
  type = string
  default = "feather-ai-dev"
}

variable "region" {
  default = "us-east-2"
}

variable "aws_access_key_id" {
  default = "not_set"
}
variable "aws_secret_access_key" {
  default = "not_set"
}
variable "stripe_webhook_secret_key" {
  default = "not_set"
}
variable "stripe_secret_key" {
  default = "not_set"
}

variable "model_jwt_secret_key" {
  default = "not_set"
}

variable "availability_zone_a" {
  default = "us-east-2a"
}

variable "availability_zone_b" {
  default = "us-east-2b"
}

variable "db_password" {
  default = "not_set"
}

variable "storage_main" {
  default = "feather-ai-dev-front-storage"
}