terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

resource "aws_api_gateway_rest_api" "chat_rest_api" {
  name        = "chat-rest-api"
  description = "Chat RestAPI"
  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_request_validator" "full_validator" {
  name                        = "full-validator"
  rest_api_id                 = aws_api_gateway_rest_api.chat_rest_api.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_model" "make_room_request" {
  name         = "MakeRoomRequest"
  rest_api_id  = aws_api_gateway_rest_api.chat_rest_api.id
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

data "archive_file" "messages_function_archive" {
  type       = "zip"
  source_dir = "${path.root}/../chat/messages"
  excludes = [
    "venv",
    "_pycache_"
  ]
  output_path = "${path.root}/.terraform/temp/messages.zip"
}

resource "aws_lambda_function" "chat-messages-function" {
  function_name = "chat-messages-function"
  description   = "Part of Chat: rooms and messages APIs"
  runtime       = "python3.12"
  role          = var.chat_role_arn
  layers = [
    var.chat_layer_arn
  ]
  filename = data.archive_file.messages_function_archive.output_path
  handler  = "app.handler"
  timeout  = 5
  environment {
    variables = {
      CHAT_DB : var.chat_db
    }
  }
}

resource "aws_api_gateway_resource" "rooms_resource" {
  rest_api_id = aws_api_gateway_rest_api.chat_rest_api.id
  parent_id   = aws_api_gateway_rest_api.chat_rest_api.root_resource_id
  path_part   = "rooms"
}


resource "aws_api_gateway_resource" "room_detail_resource" {
  rest_api_id = aws_api_gateway_rest_api.chat_rest_api.id
  parent_id   = aws_api_gateway_resource.rooms_resource.id
  path_part   = "{roomId}"
}

resource "aws_api_gateway_resource" "messages_resource" {
  rest_api_id = aws_api_gateway_rest_api.chat_rest_api.id
  parent_id   = aws_api_gateway_resource.room_detail_resource.id
  path_part   = "messages"
}

resource "aws_api_gateway_resource" "message_detail_resource" {
  rest_api_id = aws_api_gateway_rest_api.chat_rest_api.id
  parent_id   = aws_api_gateway_resource.messages_resource.id
  path_part   = "{messageId}"
}


#Globals:
#  Function:
#    Runtime: python3.12
#    MemorySize: 128
#    Handler: app.handler
#    Timeout: 5
#    Environment:
#      Variables:
#        AUTH_DB: !Ref HvrIamDatabase
#        CHAT_DB: !Ref ChatDatabaseName
#        REGION: !Ref AWS::Region
#
#Mappings:
#  Environment:
#    dev:
#      # come from HvrChatFoundationFormation
#      ApiRole: 'arn:aws:iam::262801217559:role/HvrChatFoundationFormation-ApiGatewayRole-CVvKZZnuJSeS'
#      ChatRole: 'arn:aws:iam::262801217559:role/HvrChatFoundationFormation-ChatRole-w0gczFTKOfRe'
#      ChatAuthorizer: 'arn:aws:lambda:ca-central-1:262801217559:function:ChatAuthorizerFunction'
#      # comes from HvrChatWsFormation
#      ChatMessagesFunction: 'arn:aws:lambda:ca-central-1:262801217559:function:ChatMessagesFunction'
#      # created manually
#      ChatApiSslCertificate: 'arn:aws:acm:us-east-1:262801217559:certificate/f2a6727c-5425-4b12-91ac-8b126db65f86'
#      ChatApiDomainName: 'dev.chat.hvrinternal.com'
#      WsApiCustomDomainName: 'https://dev.channel.hvrinternal.com'
#      Pusher: 'arn:aws:lambda:ca-central-1:262801217559:function:Pusher'
#
#    prod:
#      # come from HvrChatFoundationFormation
#      ApiRole: 'arn:aws:iam::666173361738:role/HvrChatFoundationFormation-ApiGatewayRole-0C4oo1lQhkDg'
#      ChatRole: 'arn:aws:iam::666173361738:role/HvrChatFoundationFormation-ChatRole-1OCFvJiPlAF1'
#      ChatAuthorizer: 'arn:aws:lambda:ca-central-1:666173361738:function:ChatAuthorizerFunction'
#      # comes from HvrChatWsFormation
#      ChatMessagesFunction: 'arn:aws:lambda:ca-central-1:666173361738:function:ChatMessagesFunction'
#      # created manually
#      ChatApiSslCertificate: 'arn:aws:acm:us-east-1:666173361738:certificate/0424797f-ce76-4030-812a-b50f65b211b2'
#      ChatApiDomainName: 'chat.hvrinternal.com'
#      WsApiCustomDomainName: 'https://channel.hvrinternal.com'
#      Pusher: 'arn:aws:lambda:ca-central-1:666173361738:function:Pusher'
#


#  RoomsResourceAuthorizer:
#    Type: AWS::ApiGateway::Authorizer
#    Properties:
#      AuthorizerUri: !Sub
#        - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#        - function: !FindInMap [ Environment, !Ref Environment, ChatAuthorizer ]
#          region: !Ref AWS::Region
#      IdentitySource: "method.request.header.Authorization"
#      Name: "rooms-authorizer"
#      RestApiId: !Ref ChatRestApi
#      Type: REQUEST
#
#  GetRoomMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: GET
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !FindInMap [ Environment, !Ref Environment, ChatMessagesFunction ]
#      OperationName: "get-room"
#      MethodResponses:
#        - StatusCode: 200
#      RequestParameters:
#        method.request.path.roomId: true
#      ResourceId: !Ref RoomDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  GetRoomsMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: GET
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !FindInMap [ Environment, !Ref Environment, ChatMessagesFunction ]
#      OperationName: "get-rooms"
#      MethodResponses:
#        - StatusCode: 200
#      ResourceId: !Ref RoomsResource
#      RestApiId: !Ref ChatRestApi
#
#  MakeRoomMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: POST
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !FindInMap [ Environment, !Ref Environment, ChatMessagesFunction ]
#      OperationName: "make-room"
#      MethodResponses:
#        - StatusCode: 200
#      RequestModels:
#        application/json: !Ref MakeRoomRequest
#      RequestValidatorId: !Ref FullValidator
#      ResourceId: !Ref RoomsResource
#      RestApiId: !Ref ChatRestApi
#
#  EditRoomMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: PUT
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ChatRole ]
#        IntegrationHttpMethod: POST
#        IntegrationResponses:
#          - SelectionPattern: "2\\d{2}"
#            StatusCode: 200
#            ResponseTemplates:
#              application/json: !Sub |
#                #set($room = $input.path('$.Attributes'))
#                {
#                  "room": {
#                    "id": "$room.roomId.S",
#                    "name": "$room.roomName.S",
#                    "joinedAt": "$room.joinedAt.S",
#                    "unread": "$room.unread.N",
#                    "userId": "$room.userId.S",
#                    "avatar": "$room.avatar.S",
#                    "latestMessage": {
#                      "body": "$room.latestMessage.M.body.S",
#                      "by": {
#                        "userId": "$room.latestMessage.M.madeBy.M.userId.S",
#                        "username": "$room.latestMessage.M.madeBy.M.username.S"
#                      },
#                      #set($editedAt = $room.latestMessage.M.editedAt.S)
#                      #if($editedAt != "")
#                        "editedAt": "$editedAt",
#                      #end
#                        "createdAt": "$room.latestMessage.M.createdAt.S",
#                        "clientId": "$room.latestMessage.M.clientId.S"
#                    }
#                  }
#                }
#          - ResponseTemplates:
#              application/json: |
#                #set($response = $input.path('$'))
#                #if($response.toString().contains("ConditionalCheckFailedException"))
#                  {
#                    "error": true,
#                    "message": "Room not found"
#                  }
#                #end
#            SelectionPattern: "4\\d{2}"
#            StatusCode: 404
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#        RequestTemplates:
#          application/json: !Sub |
#            #set($roomId = $input.params('roomId'))
#            {
#              "TableName": "${ChatDatabaseName}",
#              "Key": {
#                  "PK": {"S": "USER#$context.authorizer.principalId"},
#                  "SK": {"S": "ROOM#$roomId"}
#              },
#              "ConditionExpression": "attribute_exists(#PK) AND attribute_exists(#SK)",
#              "UpdateExpression": "SET #unread = :unread",
#              "ExpressionAttributeNames": {
#                "#PK": "PK",
#                "#SK": "SK",
#                "#unread": "unread"
#              },
#              "ExpressionAttributeValues": {
#                ":unread": {"N": "0"}
#              },
#              "ReturnValues": "ALL_NEW"
#            }
#        Type: AWS
#        Uri: !Sub "arn:aws:apigateway:${AWS::Region}:dynamodb:action/UpdateItem"
#      OperationName: "edit-room"
#      MethodResponses:
#        - StatusCode: 200
#        - StatusCode: 404
#      RequestParameters:
#        method.request.path.roomId: true
#      ResourceId: !Ref RoomDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  DeleteRoomMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: DELETE
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ChatRole ]
#        IntegrationHttpMethod: POST
#        IntegrationResponses:
#          - SelectionPattern: "2\\d{2}"
#            StatusCode: 204
#          - ResponseTemplates:
#              application/json: |
#                #set($response = $input.path('$'))
#                #if($response.toString().contains("ConditionalCheckFailedException"))
#                  {
#                    "error": true,
#                    "message": "Room not found"
#                  }
#                #end
#            SelectionPattern: "4\\d{2}"
#            StatusCode: 404
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#        RequestTemplates:
#          application/json: !Sub |
#            #set($roomId = $input.params('roomId'))
#            #set($user = $util.parseJson($context.authorizer.user))
#            #set($userId = $user.userId.S)
#            {
#              "TableName": "${ChatDatabaseName}",
#              "Key": {
#                  "PK": {"S": "USER#$userId"},
#                  "SK": {"S": "ROOM#$roomId"}
#              },
#              "ConditionExpression": "attribute_exists(#PK) AND attribute_exists(#SK)",
#              "ExpressionAttributeNames": {
#                "#PK": "PK",
#                "#SK": "SK"
#              }
#            }
#        Type: AWS
#        Uri: !Sub "arn:aws:apigateway:${AWS::Region}:dynamodb:action/DeleteItem"
#      OperationName: "delete-room"
#      MethodResponses:
#        - StatusCode: 204
#        - StatusCode: 404
#      RequestParameters:
#        method.request.path.roomId: true
#      ResourceId: !Ref RoomDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  GetMessageMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: GET
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ChatRole ]
#        IntegrationHttpMethod: POST
#        IntegrationResponses:
#          - SelectionPattern: 200
#            StatusCode: 200
#            ResponseTemplates:
#              application/json: !Sub |
#                #set($message = $input.path('$.Item'))
#                #set($messageId = $message.id.S)
#
#                #if ($messageId == "")
#                #set($context.responseOverride.status = 404)
#                {
#                  "error": true,
#                  "message": "Message not found"
#                }
#                #else
#                {
#                  "id": "$messageId",
#                  "body": "$util.escapeJavaScript($message.body.S)",
#                  "createdAt": "$message.createdAt.S",
#                #set($editedAt = $message.editedAt.S)
#                #if($editedAt != "")
#                  "editedAt": "$editedAt",
#                #end
#                #set($to = $message.to)
#                #if($to != "")
#                  "to": {
#                      "id": "$to.M.id.S",
#                      "body": "$util.escapeJavaScript($to.M.body.S)",
#                      "createdAt": "$to.M.createdAt.S",
#                      "roomId": "$to.M.roomId.S",
#                      "clientId": "$to.M.clientId.S",
#                      "madeBy": {
#                        "userId": "$to.M.madeBy.M.userId.S",
#                        "username": "$to.M.madeBy.M.username.S"
#                      }
#                    },
#                #end
#                  "roomId": "$message.roomId.S",
#                  "clientId": "$message.clientId.S",
#                  "madeBy": {
#                    "userId": "$message.madeBy.M.userId.S",
#                    "username": "$message.madeBy.M.username.S"
#                  }
#                }
#                #end
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#          integration.request.path.messageId: method.request.path.messageId
#        RequestTemplates:
#          application/json: !Sub |
#            {
#              "TableName": "${ChatDatabaseName}",
#              "Key": {
#                "PK": {"S": "ROOM#$input.params('roomId')"},
#                "SK": {"S": "MSG#$input.params('messageId')"}
#              }
#            }
#        Type: AWS
#        Uri: !Sub "arn:aws:apigateway:${AWS::Region}:dynamodb:action/GetItem"
#      OperationName: "get-message"
#      MethodResponses:
#        - StatusCode: 200
#        - StatusCode: 404
#      RequestParameters:
#        method.request.path.roomId: true
#        method.request.path.messageId: true
#      ResourceId: !Ref MessageDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  GetMessagesMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: GET
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#          integration.request.querystring.anchor: method.request.querystring.anchor
#          integration.request.querystring.pageSize: method.request.querystring.pageSize
#          integration.request.querystring.desc: method.request.querystring.desc
#          integration.request.querystring.inclusive: method.request.querystring.inclusive
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !FindInMap [ Environment, !Ref Environment, ChatMessagesFunction ]
#      OperationName: "get-messages"
#      MethodResponses:
#        - StatusCode: 200
#      RequestParameters:
#        method.request.path.roomId: true
#        method.request.querystring.pageSize: false
#        method.request.querystring.desc: false
#        method.request.querystring.anchor: false
#        method.request.querystring.inclusive: false
#      ResourceId: !Ref MessagesResource
#      RestApiId: !Ref ChatRestApi
#
#  SendMessageMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: POST
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !FindInMap [ Environment, !Ref Environment, ChatMessagesFunction ]
#      OperationName: "send-message"
#      MethodResponses:
#        - StatusCode: 200
#      RequestParameters:
#        method.request.path.roomId: true
#      RequestModels:
#        application/json: !Ref SendMessageRequest
#      RequestValidatorId: !Ref FullValidator
#      ResourceId: !Ref MessagesResource
#      RestApiId: !Ref ChatRestApi
#
#  EditMessageMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: PUT
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ApiRole ]
#        IntegrationHttpMethod: POST
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#          integration.request.path.messageId: method.request.path.messageId
#        Type: AWS_PROXY
#        Uri: !Sub
#          - "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${function}/invocations"
#          - region: !Ref AWS::Region
#            function: !GetAtt ChatMessagesFunction.Arn
#      OperationName: "edit-message"
#      MethodResponses:
#        - StatusCode: 200
#      RequestParameters:
#        method.request.path.roomId: true
#        method.request.path.messageId: true
#      RequestModels:
#        application/json: !Ref SendMessageRequest
#      RequestValidatorId: !Ref FullValidator
#      ResourceId: !Ref MessageDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  DeleteMessageMethod:
#    Type: AWS::ApiGateway::Method
#    Properties:
#      AuthorizationType: CUSTOM
#      AuthorizerId: !Ref RoomsResourceAuthorizer
#      HttpMethod: DELETE
#      Integration:
#        Credentials: !FindInMap [ Environment, !Ref Environment, ChatRole ]
#        IntegrationHttpMethod: POST
#        IntegrationResponses:
#          - SelectionPattern: "2\\d{2}"
#            StatusCode: 204
#          - ResponseTemplates:
#              application/json: |
#                #set($response = $input.path('$'))
#                #if($response.toString().contains("ConditionalCheckFailedException"))
#                  {
#                    "error": true,
#                    "message": "Room not found"
#                  }
#                #end
#            SelectionPattern: "4\\d{2}"
#            StatusCode: 404
#        RequestParameters:
#          integration.request.path.roomId: method.request.path.roomId
#          integration.request.path.messageId: method.request.path.messageId
#        RequestTemplates:
#          application/json: !Sub |
#            #set($roomId = $input.params('roomId'))
#            #set($messageId = $input.params('messageId'))
#            #set($user = $util.parseJson($context.authorizer.user))
#            #set($userId = $user.userId.S)
#            {
#              "TableName": "${ChatDatabaseName}",
#              "Key": {
#                  "PK": {"S": "ROOM#$roomId"},
#                  "SK": {"S": "MSG#$messageId"}
#              },
#              "ConditionExpression": "attribute_exists(#PK) AND attribute_exists(#SK) AND #user.#userId = :userId",
#              "ExpressionAttributeNames": {
#                "#PK": "PK",
#                "#SK": "SK",
#                "#user": "madeBy",
#                "#userId": "userId"
#              },
#              "ExpressionAttributeValues": {
#                ":userId": {"S": "$userId"}
#              }
#            }
#        Type: AWS
#        Uri: !Sub "arn:aws:apigateway:${AWS::Region}:dynamodb:action/DeleteItem"
#      OperationName: "delete-message"
#      MethodResponses:
#        - StatusCode: 204
#        - StatusCode: 404
#      RequestParameters:
#        method.request.path.roomId: true
#        method.request.path.messageId: true
#      ResourceId: !Ref MessageDetailResource
#      RestApiId: !Ref ChatRestApi
#
#  RestApiDeployment:
#    Type: AWS::ApiGateway::Deployment
#    DependsOn: DeleteMessageMethod
#    Properties:
#      RestApiId: !Ref ChatRestApi
#
#  RestApiStage:
#    Type: AWS::ApiGateway::Stage
#    Properties:
#      RestApiId: !Ref ChatRestApi
#      StageName: "api"
#      DeploymentId: !Ref RestApiDeployment
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
#Outputs:
#  ApiId:
#    Description: REST API ID
#    Value: !Ref ChatRestApi
#    Export:
#      Name: !Sub "${AWS::StackName}-ApiId"
#  RestApiDomainName:
#    Description: Rest API's distribution domain name
#    Value: !GetAtt ChatRestApiCustomDomainName.DistributionDomainName
#    Export:
#      Name: !Sub "${AWS::StackName}-DistributionDomainName"
