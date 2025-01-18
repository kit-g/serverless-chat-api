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

variable "chat_authorizer_function" {
  type        = string
  description = "Authorizer's function invoke URI"
}

variable "api_role" {
  type        = string
  description = "IAM role for API Gateway to call lambdas"

}
