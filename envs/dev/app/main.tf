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
    # default_tags: 이 provider로 생성되는 모든 리소스에 자동으로 태그 적용
    # 모듈 내부에서 tags를 일일이 전달하지 않아도 공통 태그가 보장됨
  }
}

module "app" {
  source = "../../../modules/app"

  name             = var.name
  instance_type    = var.instance_type
  min_size         = var.min_size
  max_size         = var.max_size
  desired_size     = var.desired_size
  cpu_target_value = var.cpu_target_value

  # ── network 레이어에서 가져오는 값 ──────────────────────────────
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  # Private NAT 서브넷: 인터넷 직접 접근 불가, NAT GW를 통해 아웃바운드만 허용
  # App 서버는 ALB 뒤에 위치해 직접 노출되지 않아야 함 (보안)
  subnet_ids = data.terraform_remote_state.network.outputs.private_nat_subnet_ids

  # ── security 레이어에서 가져오는 값 ─────────────────────────────
  # app_sg: ALB에서 8080 포트 인바운드 허용, DB로 3306 아웃바운드 허용
  security_group_id = data.terraform_remote_state.security.outputs.sg_ids["app_sg"]

  # app_role Instance Profile: SSM, CloudWatch, Secrets Manager 접근 권한 포함
  iam_instance_profile_arn = data.terraform_remote_state.security.outputs.iam_instance_profile_arns["app_role"]

  # ── web 레이어에서 가져오는 값 ──────────────────────────────────
  # ASG가 새 인스턴스를 시작할 때 이 Target Group에 자동으로 등록됨
  target_group_arn = data.terraform_remote_state.web.outputs.target_group_arn

  tags = var.tags
}
