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
