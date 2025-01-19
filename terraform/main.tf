terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}


module "foundation" {
  source  = "./modules/foundation"
  chat_db = var.chat_db
}

module "rest" {
  source = "./modules/rest"
  depends_on = [
    module.foundation
  ]
  chat_db                     = var.chat_db
  api_role                    = module.foundation.api_role
  chat_authorizer_function    = module.foundation.chat_authorizer_function
  chat_layer_arn              = module.foundation.chat_layer_arn
  chat_role_arn               = module.foundation.chat_role_arn
  api_gateway_ssl_certificate = var.api_gateway_ssl_certificate
  custom_domain_name          = var.custom_domain_name
}
