terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = var.tags
  }
}

module "alb" {
  source = "../../../modules/web"

  name              = var.name
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids        = data.terraform_remote_state.network.outputs.public_subnet_ids
  security_group_id = data.terraform_remote_state.security.outputs.sg_ids["alb_sg"]
  # certificate_arn은 도메인 확보 후 아래 주석을 해제
  # certificate_arn = data.terraform_remote_state.security.outputs.acm_regional_arns["alb_cert"]
  tags              = var.tags
  enable_cloudfront = true
}
