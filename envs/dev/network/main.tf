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

locals {
  # AZ를 키로 사용하는 맵 구조.
  # 이유: 리스트+인덱스 방식은 AZ 순서가 바뀌면 기존 서브넷이 삭제/재생성되는 위험이 있다.
  # 맵 방식은 AZ 이름이 키이므로 순서 변경에 영향받지 않는다.
  # var.cidr은 실행 시점에 결정되므로 variable default가 아닌 locals에서 계산한다.
  subnet_config = {
    "ap-northeast-2a" = { public = cidrsubnet(var.cidr, 8, 1), nat = cidrsubnet(var.cidr, 8, 11), full = cidrsubnet(var.cidr, 8, 21) }
    "ap-northeast-2c" = { public = cidrsubnet(var.cidr, 8, 2), nat = cidrsubnet(var.cidr, 8, 12), full = cidrsubnet(var.cidr, 8, 22) }
  }
}

module "main" {
  source = "../../../modules/network"
  # source는 디렉토리 경로를 가리킵니다. 파일(main.tf)이 아닙니다.
  # Terraform은 해당 디렉토리의 모든 .tf 파일을 자동으로 로드합니다.
  name = var.name
  cidr = var.cidr
  tags = var.tags
  # tags를 모듈에도 전달하는 이유: modules/vpc의 merge()가 Name 태그를 추가하기 때문입니다.
  # provider default_tags + 모듈 내 merge() = 완전한 태그 세트가 됩니다.

  # subnet_config에서 서브넷 타입별로 { az => cidr } 맵을 추출해서 전달한다.
  # for expression: { for 키, 값 in 원본맵 : 새키 => 새값 }
  public_subnet_cidrs       = { for az, cfg in local.subnet_config : az => cfg.public }
  private_nat_subnet_cidrs  = { for az, cfg in local.subnet_config : az => cfg.nat }
  private_full_subnet_cidrs = { for az, cfg in local.subnet_config : az => cfg.full }
}
