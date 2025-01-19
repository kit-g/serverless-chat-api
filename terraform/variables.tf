variable "region" {
  type        = string
  description = "AWS region"
}

variable "chat_db" {
  type        = string
  description = "Chat DynamoDB table"
  default     = "chat-db"
}

variable "profile" {
  type        = string
  description = "AWS profile, usually 'default'"
}

variable "api_gateway_ssl_certificate" {
  type        = string
  description = "Optional AWS ACM certificate ARN, in case custom DNS name is provided"
}

variable "custom_domain_name" {
  type        = string
  description = "Optional DNS name to attach to the API Gateway"
}

variable "chat_lib_path" {
  type        = string
  description = "Local relative (to terraform root) path to where chatlib package is zipped"
}
