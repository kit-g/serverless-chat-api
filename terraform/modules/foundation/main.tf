terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_dynamodb_table" "chat_database" {
  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
  name         = var.chat_db
  hash_key     = "PK"
  range_key    = "SK"
  global_secondary_index {
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    name            = "GSI1"
    projection_type = "KEYS_ONLY"
  }
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

resource "aws_iam_policy" "database_read_policy" {
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "dynamodb:GetItem",
            "dynamodb:Query",
            "dynamodb:BatchGetItem"
          ],
          "Resource" : [
            "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.chat_db}",
            "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.chat_db}/*"
          ]
        }
      ]
    }
  )
  name = "DatabaseReadPolicy"
}

resource "aws_iam_policy" "database_write_policy" {
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:BatchWriteItem",
            "dynamodb:DeleteItem"
          ],
          "Resource" : [
            "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.chat_db}",
          ]
        }
      ]
    }
  )
  name = "DatabaseWritePolicy"
}

resource "aws_iam_policy" "api_write_policy" {
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "execute-api:ManageConnections",
            "execute-api:Invoke",
          ],
          "Resource" : [
            "arn:aws:execute-api:*:${data.aws_caller_identity.current.account_id}:*/*/*/*",
          ]
        }
      ]
    }
  )
  name = "ApiWritePolicy"
}

resource "aws_iam_policy" "stream_policy" {
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "dynamodb:DescribeStream",
            "dynamodb:GetRecords",
            "dynamodb:GetShardIterator",
            "dynamodb:ListStreams",
          ],
          "Resource" : [
            "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.chat_db}/stream/*",
          ]
        }
      ]
    }
  )
  name = "StreamPolicy"
}

resource "aws_iam_role" "chat_role" {
  name = "ChatRole"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = [
              "lambda.amazonaws.com",
              "apigateway.amazonaws.com"
            ]
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role" "message_stream_role" {
  name = "MessageStreamRole"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = [
              "lambda.amazonaws.com",
            ]
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_policy_attachment" "chat_api_write" {
  name       = "chat-api-write-attachment"
  policy_arn = aws_iam_policy.api_write_policy.arn
  roles = [
    aws_iam_role.chat_role.name,
    aws_iam_role.message_stream_role.name
  ]
}

resource "aws_iam_policy_attachment" "database_write" {
  name       = "database-write-attachment"
  policy_arn = aws_iam_policy.database_write_policy.arn
  roles = [
    aws_iam_role.chat_role.name,
    aws_iam_role.message_stream_role.name
  ]
}

resource "aws_iam_policy_attachment" "database_read" {
  name       = "database-read-attachment"
  policy_arn = aws_iam_policy.database_read_policy.arn
  roles = [
    aws_iam_role.chat_role.name,
    aws_iam_role.message_stream_role.name
  ]
}

resource "aws_iam_policy_attachment" "lambda-role-attachment" {
  name       = "lambda-role-attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  roles = [
    aws_iam_role.chat_role.name,
    aws_iam_role.message_stream_role.name
  ]
}

resource "aws_lambda_layer_version" "chat_layer" {
  layer_name  = "chat-layer"
  description = "Chat lib layer"
  filename    = "${path.root}/../chatmodels/chat-lib-0-0-1.zip"
  compatible_runtimes = ["python3.12"] # Python 3.13 unsupported?
}

data "archive_file" "authorizer_function_archive" {
  type        = "zip"
  source_dir  = "${path.root}/../chat/authorizer"
  output_path = "${path.root}/.terraform/temp/authorizer.zip"
}

resource "aws_lambda_function" "chat_authorizer" {
  function_name = "chat-authorizer-function"
  description   = "Part of Chat: handles authorization"
  role          = aws_iam_role.chat_role.arn
  handler       = "app.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.authorizer_function_archive.output_path
  environment {
    variables = {
      REGION  = data.aws_region.current.name
      ACCOUNT = data.aws_caller_identity.current.account_id
    }
  }
  layers = [
    aws_lambda_layer_version.chat_layer.arn
  ]
}

resource "aws_lambda_permission" "chat_authorizer" {
  function_name = aws_lambda_function.chat_authorizer.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "ApiGatewayRole"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "apigateway.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_policy" "invoke_lambda_policy" {
  name = "InvokeLambda"
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = "lambda:InvokeFunction"
          Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:chat*"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "invoke_lambda_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.invoke_lambda_policy.arn
}


output "chat_layer_arn" {
  value       = aws_lambda_layer_version.chat_layer.arn
  description = "The ARN of the Chat Lambda layer"
}

output "chat_role_arn" {
  value       = aws_iam_role.chat_role.arn
  description = "IAM role for the main chat function"
}

output "message_stream_role" {
  value       = aws_iam_role.message_stream_role.arn
  description = "IAM role for the DynamoDb stream function function"
}

output "chat_authorizer_function" {
  value       = aws_lambda_function.chat_authorizer.invoke_arn
  description = "Lambda function that authenticates all requests"
}

output "api_role" {
  value       = aws_iam_role.api_gateway_role.arn
  description = "IAM role for API Gateway to call lambdas"
}
