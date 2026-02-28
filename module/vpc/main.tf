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

resource "aws_vpc" "main" {
  cidr_block = var.cidr
  tags = merge(
    var.tags,
    {
      Name="${var.name}-vpc"
    }
  )
}

variable "name" {
  type=string
}

variable "tags" {
  type=map(string)
  default = {}
}

variable "cidr" {
  type = string
}

