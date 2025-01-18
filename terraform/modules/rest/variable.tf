variable "chat_layer_arn" {
  type        = string
  description = "The ARN of the Chat Lambda layer"
}

variable "chat_role_arn" {
  type        = string
  description = "IAM role for the main chat function"
}

variable "chat_db" {
  type        = string
  description = "Chat DynamoDB table"
}
