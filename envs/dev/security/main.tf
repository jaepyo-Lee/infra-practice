terraform {
  required_version = ">= 1.0.0" # Ensure that the Terraform version is 1.0.0 or higher

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specify the source of the AWS provider
      version = "~> 4.0"        # Use a version of the AWS provider that is compatible with version
    }
  }
}

provider "aws" {
  region = "ap-northeast-2" # Set the AWS region to US East (N. Virginia)
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
}
