terraform {
  required_version = ">= 1.0.0" # Ensure that the Terraform version is 1.0.0 or higher

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specify the source of the AWS provider
      version = "~> 4.0"        # Use a version of the AWS provider that is compatible with version
    }
  }
}

# 기본 provider — alias 없는 provider가 반드시 있어야 한다
# alias만 있으면 SG, IAM 등 다른 리소스들이 어느 provider를 쓸지 모름
provider "aws" {
  region = "ap-northeast-2"
}

# ALB용 ACM provider alias (언더스코어만 허용, 하이픈 불가)
provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"
}

# CloudFront용 ACM provider alias
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "security_group" {
  source = "../../../modules/security"
  vpc_id =data.terraform_remote_state.network.outputs.vpc_id
  sg = local.security_groups
  sg_rules = local.sg_rules
  iam_roles = {
    "app_role" = {
      name        = "dev-app-role"
      description = "EC2 App Server Role"
      assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { Service = "ec2.amazonaws.com" }
          Action    = "sts:AssumeRole"
        }]
      })
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",   # Session Manager
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",    # CloudWatch Logs
        "arn:aws:iam::aws:policy/SecretsManagerReadWrite",        # Secrets Manager
      ]
    }
  }

  secret_manager_meta = {
    rds_credentials = {
      name                    = "myapp/dev/rds-credentials"
      description             = "Dev RDS 접속 자격증명"
      recovery_window_in_days = 0  # 실습 환경: 즉시 삭제 가능
      secret_value = jsonencode({
        username = "admin"
        password = "change-me-before-apply"  # 실제 값은 apply 전 교체 또는 수동 업데이트
        host     = "TBD"  # RDS 구현 후 업데이트
        port     = 3306
      })
    }
  }

  /*acm = {
    # ALB용 인증서 — ap-northeast-2 (is_global = false)
    "alb_cert" = {
      domain_name               = "api.example.com"
      validation_method         = "DNS"
      subject_alternative_names = []
      is_global                 = false
    }
    # CloudFront용 인증서 — us-east-1 (is_global = true)
    "cf_cert" = {
      domain_name               = "example.com"
      validation_method         = "DNS"
      subject_alternative_names = ["www.example.com"]
      is_global                 = true
    }
  }*/

  providers = {
    aws                = aws              # 기본 provider (SG, IAM, NACL 등)
    aws.us_east_1      = aws.us_east_1   # CloudFront용 ACM
    aws.ap_northeast_2 = aws.ap_northeast_2 # ALB용 ACM
  }


}
