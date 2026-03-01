terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}
# modules/vpc/main.tf
# VPC 모듈의 핵심 리소스만 정의합니다.
# variable, output은 각각 variables.tf, outputs.tf로 분리하는 것이 Terraform 컨벤션입니다.
# 이유: 파일 역할이 명확해져 팀 협업과 유지보수가 쉬워집니다.

resource "aws_vpc" "vpc" {
  cidr_block = var.cidr

  # DNS 옵션 두 가지를 명시적으로 활성화합니다.
  # enable_dns_support   = true: AWS 내부 DNS 서버(169.254.169.253)를 통해 이름 해석을 허용합니다.
  # enable_dns_hostnames = true: 퍼블릭 IP를 가진 EC2 인스턴스에 퍼블릭 DNS 호스트네임을 부여합니다.
  # 이 두 옵션이 활성화되지 않으면 ECS, RDS, ALB 등 서비스가 DNS로 서로를 찾지 못할 수 있습니다.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      # Name 태그는 AWS 콘솔에서 리소스를 식별하는 유일한 수단입니다.
      # "${var.name}-vpc" 패턴으로 환경별 구분이 됩니다 (예: dev-vpc, prod-vpc).
      Name = "${var.name}-vpc"
    }
  )
}

resource "aws_subnet" "subnet" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = ""
  availability_zone = ""
  map_public_ip_on_launch = false
}