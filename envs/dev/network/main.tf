# envs/dev/vpc/main.tf
# dev 환경의 VPC 스택 진입점입니다.
# 이 파일에는 terraform 설정, provider, module 호출만 포함합니다.
# 이유: 리소스를 직접 여기에 쓰면 모듈화의 이점(재사용, 환경 분리)이 사라집니다.

terraform {
  required_version = ">= 1.5.0"
  # required_version을 명시하는 이유: 팀원이나 CI/CD 파이프라인이 다른 버전의 Terraform을
  # 사용하면 state 파일 비호환 또는 문법 오류가 발생할 수 있습니다.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # ~> 5.0의 의미: 5.x 마이너 업데이트는 허용하지만 6.0으로의 메이저 업그레이드는 차단합니다.
      # provider 버전을 고정하는 이유: 갑작스러운 breaking change로 인한 장애를 방지합니다.
    }
  }
}

provider "aws" {
  region = "ap-northeast-2" # 서울 리전
  # 리전을 하드코딩하지 않고 variable로 만들 수도 있습니다.
  # 단일 리전 프로젝트라면 여기에 고정하는 것이 더 명확합니다.

  default_tags {
    tags = var.tags
    # default_tags를 사용하는 이유: provider 수준에서 태그를 설정하면
    # 이 환경의 모든 리소스에 자동으로 태그가 적용됩니다.
    # 각 module 호출마다 tags를 일일이 전달하지 않아도 됩니다.
  }
}