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
  type = string
  description = "AWS profile, usually 'default'"
}
