# envs/dev/vpc/variables.tf
# dev 환경의 vpc 스택이 받는 입력 변수를 선언합니다.
# 실제 값은 terraform.tfvars에서 주입하거나, default를 그대로 사용합니다.
# 이유: 환경별 값(dev vs prod)을 코드가 아닌 변수로 분리해야 동일한 모듈을 재사용할 수 있습니다.

variable "name" {
  type        = string
  description = "환경 이름. 리소스 네이밍 prefix로 사용됩니다 (예: dev, prod)"
  default     = "dev"
  # default = "dev": dev 환경의 기본값입니다.
  # terraform.tfvars에서 name = "dev-ap" 처럼 재정의할 수 있습니다.
}

variable "cidr" {
  type        = string
  description = "VPC CIDR 블록. /16을 사용하면 서브넷을 최대 256개까지 나눌 수 있습니다."
  default     = "10.0.0.0/16"
  # /16을 사용하는 이유: Public(x2), Private-App(x2), Private-DB(x2) 등 6개 이상의 서브넷을
  # 여유 있게 배치하려면 /16이 필요합니다. /24는 단일 서브넷 크기입니다.
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그. 비용 대시보드 필터링, 환경 식별에 활용됩니다."
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
    # Environment: 어떤 환경의 리소스인지 구분합니다 (dev/prod/staging).
    # ManagedBy  : 이 리소스가 Terraform으로 관리됨을 명시합니다. 수동 변경을 방지하는 신호입니다.
  }
}
