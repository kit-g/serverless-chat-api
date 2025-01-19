variable "chat_db" {
  type        = string
  description = "Chat DynamoDB table"
}

variable "chat_lib_path" {
  type        = string
  description = "Local relative (to terraform root) path to where chatlib package is zipped"
}
