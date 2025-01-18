variable "region" {
  type        = string
  description = "AWS region"
}

variable "environment" {
  type        = string
  description = "Logical environment"
}

variable "auth_db" {
  type        = string
  description = "Authentication DynamoDB table name"
}

variable "chat_db" {
  type        = string
  description = "Chat DynamoDB table"
}
