terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "chat" {
  name        = "chat"
  description = "Chat RestAPI"
  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_request_validator" "full" {
  name                        = "full-validator"
  rest_api_id                 = aws_api_gateway_rest_api.chat.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_model" "make_room_request" {
  name         = "MakeRoomRequest"
  rest_api_id  = aws_api_gateway_rest_api.chat.id
  content_type = "application/json"
  description  = "Create Room request payload"
  schema = jsonencode(
    {
      "$schema" : "http://json-schema.org/draft-04/schema#",
      "title" : "MakeRoomRequest",
      "type" : "object",
      "properties" : {
        "with" : {
          "type" : "array",
          "items" : {
            "type" : "string"
          },
          "uniqueItems" : true,
          "minItems" : 2
        },
        "roomId" : {
          "type" : "string",
          "minLength" : 1
        }
      },
      "required" : [
        "roomId",
        "with"
      ]
    }
  )
}

resource "aws_api_gateway_model" "send_message_request" {
  name         = "SendMessageRequest"
  rest_api_id  = aws_api_gateway_rest_api.chat.id
  content_type = "application/json"
  description  = "Send Message request payload"
  schema = jsonencode(
    {
      "$schema" : "http://json-schema.org/draft-04/schema#",
      "title" : "SendMessageRequest",
      "type" : "object",
      "properties" : {
        "message" : {
          "type" : "string",
          "minLength" : 1
        },
        "clientId" : {
          "type" : "string",
          "minLength" : 1
        },
        "to" : {
          "type" : "object",
          "properties" : {
            "messageId" : {
              "type" : "string",
              "minLength" : 1
            }
          }
        }
      },
      "required" : [
        "message",
        "clientId"
      ]
    }
  )
}

data "archive_file" "messages_function" {
  type       = "zip"
  source_dir = "${path.root}/../chat/messages"
  excludes = [
    "venv",
    "_pycache_"
  ]
  output_path = "${path.root}/.terraform/temp/messages.zip"
}

resource "aws_lambda_function" "chat_messages" {
  function_name = "chat-messages-function"
  description   = "Part of Chat: rooms and messages APIs"
  runtime       = "python3.12"
  role          = var.chat_role_arn
  layers = [
    var.chat_layer_arn
  ]
  filename = data.archive_file.messages_function.output_path
  handler  = "app.handler"
  timeout  = 5
  environment {
    variables = {
      CHAT_DB : var.chat_db
    }
  }
}

resource "aws_api_gateway_resource" "rooms" {
  rest_api_id = aws_api_gateway_rest_api.chat.id
  parent_id   = aws_api_gateway_rest_api.chat.root_resource_id
  path_part   = "rooms"
}

resource "aws_api_gateway_resource" "room_detail" {
  rest_api_id = aws_api_gateway_rest_api.chat.id
  parent_id   = aws_api_gateway_resource.rooms.id
  path_part   = "{roomId}"
}

resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.chat.id
  parent_id   = aws_api_gateway_resource.room_detail.id
  path_part   = "messages"
}

resource "aws_api_gateway_resource" "message_detail" {
  rest_api_id = aws_api_gateway_rest_api.chat.id
  parent_id   = aws_api_gateway_resource.messages.id
  path_part   = "{messageId}"
}

resource "aws_api_gateway_authorizer" "main" {
  name            = "rooms-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.chat.id
  type            = "REQUEST"
  authorizer_uri  = var.chat_authorizer_function
  identity_source = "method.request.querystring.username"
}

resource "aws_api_gateway_method" "get_room_method" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "GET"
  operation_name = "get-room"
  resource_id    = aws_api_gateway_resource.room_detail.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id

  request_parameters = {
    "method.request.path.roomId" : true
  }
}

resource "aws_api_gateway_integration" "get_room" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.room_detail.id
  http_method             = aws_api_gateway_method.get_room_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
  request_parameters = {
    "integration.request.path.roomId" = "method.request.path.roomId"
  }
}

resource "aws_api_gateway_method" "get_rooms" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "GET"
  operation_name = "get-rooms"
  resource_id    = aws_api_gateway_resource.rooms.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
}

resource "aws_api_gateway_integration" "get_rooms" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.rooms.id
  http_method             = aws_api_gateway_method.get_rooms.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
}

resource "aws_api_gateway_method" "make_room" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "POST"
  operation_name = "make-room"
  resource_id    = aws_api_gateway_resource.rooms.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_models = {
    "application/json" : aws_api_gateway_model.make_room_request.name
  }
  request_validator_id = aws_api_gateway_request_validator.full.id
}

resource "aws_api_gateway_integration" "make_room" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.rooms.id
  http_method             = aws_api_gateway_method.make_room.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
}

resource "aws_api_gateway_method" "edit_room" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "PUT"
  operation_name = "edit-room"
  resource_id    = aws_api_gateway_resource.room_detail.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
  }
}

resource "aws_api_gateway_integration" "edit_room" {
  credentials = var.api_role
  rest_api_id = aws_api_gateway_rest_api.chat.id
  resource_id = aws_api_gateway_resource.room_detail.id
  http_method = aws_api_gateway_method.edit_room.http_method
  type        = "MOCK"
  request_parameters = {
    "integration.request.path.roomId" : "method.request.path.roomId"
  }
  request_templates = {
    "application/json" = <<EOT
      {"statusCode": 200}
    EOT
  }
}

resource "aws_api_gateway_integration_response" "edit_room" {
  depends_on = [
    aws_api_gateway_method.edit_room,
    aws_api_gateway_integration.edit_room,
  ]
  http_method = "PUT"
  resource_id = aws_api_gateway_resource.room_detail.id
  rest_api_id = aws_api_gateway_rest_api.chat.id
  status_code = 200
  response_templates = {
    "application/json" = <<EOT
        {
          "message": "Room $input.params('roomId') has been edited"
        }
      EOT
  }
}

resource "aws_api_gateway_method_response" "edit_room_200" {
  depends_on = [
    aws_api_gateway_method.edit_room,
    aws_api_gateway_integration.edit_room,
  ]
  rest_api_id = aws_api_gateway_rest_api.chat.id
  http_method = aws_api_gateway_method.edit_room.http_method
  resource_id = aws_api_gateway_resource.room_detail.id
  status_code = 200
}

resource "aws_api_gateway_method" "delete_room" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "DELETE"
  operation_name = "delete-room"
  resource_id    = aws_api_gateway_resource.room_detail.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
  }
}

resource "aws_api_gateway_integration" "delete_room" {
  credentials = var.api_role
  rest_api_id = aws_api_gateway_rest_api.chat.id
  resource_id = aws_api_gateway_resource.room_detail.id
  http_method = aws_api_gateway_method.delete_room.http_method
  type        = "MOCK"
  request_parameters = {
    "integration.request.path.roomId" : "method.request.path.roomId"
  }
  request_templates = {
    "application/json" = <<EOT
      {"statusCode": 200}
    EOT
  }
}

resource "aws_api_gateway_method_response" "delete_room_200" {
  depends_on = [
    aws_api_gateway_method.delete_room,
    aws_api_gateway_integration.delete_room,
  ]
  rest_api_id = aws_api_gateway_rest_api.chat.id
  http_method = aws_api_gateway_method.delete_room.http_method
  resource_id = aws_api_gateway_resource.room_detail.id
  status_code = 200
}

resource "aws_api_gateway_integration_response" "delete_room" {
  depends_on = [
    aws_api_gateway_method.delete_room,
    aws_api_gateway_integration.delete_room,
  ]
  http_method = aws_api_gateway_method.delete_room.http_method
  resource_id = aws_api_gateway_resource.room_detail.id
  rest_api_id = aws_api_gateway_rest_api.chat.id
  status_code = 200
  response_templates = {
    "application/json" = <<EOT
        {
          "message": "Room $input.params('roomId') has been deleted"
        }
      EOT
  }
}

resource "aws_api_gateway_method" "get_messages" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "GET"
  operation_name = "get-messages"
  resource_id    = aws_api_gateway_resource.messages.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
  }
}

resource "aws_api_gateway_integration" "get_messages" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.messages.id
  http_method             = aws_api_gateway_method.get_messages.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
}

resource "aws_api_gateway_method" "send_message" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "POST"
  operation_name = "send-message"
  resource_id    = aws_api_gateway_resource.messages.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
  }
  request_models = {
    "application/json" : aws_api_gateway_model.send_message_request.name
  }
  request_validator_id = aws_api_gateway_request_validator.full.id
}

resource "aws_api_gateway_integration" "send_message" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.messages.id
  http_method             = aws_api_gateway_method.send_message.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
}

resource "aws_api_gateway_method" "edit_message" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "PUT"
  operation_name = "edit-message"
  resource_id    = aws_api_gateway_resource.message_detail.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
    "method.request.path.messageId" : true
  }
  request_models = {
    "application/json" : aws_api_gateway_model.send_message_request.name
  }
  request_validator_id = aws_api_gateway_request_validator.full.id
}

resource "aws_api_gateway_integration" "edit_message" {
  credentials             = var.api_role
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.message_detail.id
  http_method             = aws_api_gateway_method.edit_message.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_messages.invoke_arn
}

resource "aws_api_gateway_method" "delete_message" {
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.main.id
  http_method    = "DELETE"
  operation_name = "delete-message"
  resource_id    = aws_api_gateway_resource.message_detail.id
  rest_api_id    = aws_api_gateway_rest_api.chat.id
  request_parameters = {
    "method.request.path.roomId" : true
    "method.request.path.messageId" : true
  }
}

resource "aws_api_gateway_integration" "delete_message" {
  credentials             = var.chat_role_arn
  rest_api_id             = aws_api_gateway_rest_api.chat.id
  resource_id             = aws_api_gateway_resource.message_detail.id
  http_method             = aws_api_gateway_method.delete_message.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/DeleteItem"
  request_parameters = {
    "integration.request.path.roomId"    = "method.request.path.roomId"
    "integration.request.path.messageId" = "method.request.path.messageId"
  }
  request_templates = {
    "application/json" = <<EOT
#set($roomId = $input.params('roomId'))
#set($messageId = $input.params('messageId'))
{
  "TableName": "${var.chat_db}",
  "Key": {
      "PK": {"S": "ROOM#$roomId"},
      "SK": {"S": "MSG#$messageId"}
  },
  "ConditionExpression": "attribute_exists(#PK) AND attribute_exists(#SK)",
  "ExpressionAttributeNames": {
    "#PK": "PK",
    "#SK": "SK"
  }
}
EOT
  }
}

resource "aws_api_gateway_method_response" "delete_message_204" {
  depends_on = [
    aws_api_gateway_method.delete_message,
    aws_api_gateway_integration.delete_message,
  ]
  rest_api_id = aws_api_gateway_rest_api.chat.id
  http_method = aws_api_gateway_method.delete_message.http_method
  resource_id = aws_api_gateway_resource.message_detail.id
  status_code = 204
}

resource "aws_api_gateway_method_response" "delete_message_404" {
  depends_on = [
    aws_api_gateway_method.delete_message,
    aws_api_gateway_integration.delete_message,
  ]
  rest_api_id = aws_api_gateway_rest_api.chat.id
  http_method = aws_api_gateway_method.delete_message.http_method
  resource_id = aws_api_gateway_resource.message_detail.id
  status_code = 404
}

resource "aws_api_gateway_integration_response" "delete_message_success" {
  depends_on = [
    aws_api_gateway_method.delete_message,
    aws_api_gateway_integration.delete_message,
  ]
  http_method       = aws_api_gateway_method.delete_message.http_method
  resource_id       = aws_api_gateway_resource.message_detail.id
  rest_api_id       = aws_api_gateway_rest_api.chat.id
  status_code       = 204
  selection_pattern = "2\\d{2}"
}

resource "aws_api_gateway_integration_response" "delete_message_not_found" {
  depends_on = [
    aws_api_gateway_method.delete_message,
    aws_api_gateway_integration.delete_message,
  ]
  http_method       = aws_api_gateway_method.delete_message.http_method
  resource_id       = aws_api_gateway_resource.message_detail.id
  rest_api_id       = aws_api_gateway_rest_api.chat.id
  status_code       = 404
  selection_pattern = "4\\d{2}"
  response_templates = {
    "application/json" = <<EOT
#set($response = $input.path('$'))
#if($response.toString().contains("ConditionalCheckFailedException"))
  {
    "error": true,
    "message": "Message not found"
  }
#end
EOT
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.chat.id
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_api_gateway_integration_response.delete_room,
    aws_api_gateway_integration_response.edit_room,
  ]
}

resource "aws_api_gateway_stage" "api" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.chat.id
  stage_name    = "api"
}


#
#  ChatRestApiCustomDomainName:
#    Type: AWS::ApiGateway::DomainName
#    Properties:
#      CertificateArn: !FindInMap [ Environment, !Ref Environment, ChatApiSslCertificate ]
#      DomainName: !FindInMap [ Environment, !Ref Environment, ChatApiDomainName ]
#      SecurityPolicy: TLS_1_2
#
#  ChatRestApiPathMapping:
#    Type: AWS::ApiGateway::BasePathMapping
#    Properties:
#      DomainName: !Ref ChatRestApiCustomDomainName
#      RestApiId: !Ref ChatRestApi
#      Stage: !Ref RestApiStage
#
