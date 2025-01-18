terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

provider "aws" {
  region  = "ca-central-1"
  profile = "personal"
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
  chat_layer_arn = module.foundation.chat_layer_arn
  chat_role_arn  = module.foundation.chat_role_arn
  chat_db = var.chat_db
}
