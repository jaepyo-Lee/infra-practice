# modules/vpc/variables.tf
# 이 모듈이 외부에서 받는 입력값(인터페이스)을 선언합니다.
# type, description은 모듈 사용자가 올바른 값을 전달하도록 항상 명시해야 합니다.
# 이유: description이 없으면 `terraform-docs` 같은 문서화 도구가 동작하지 않고,
#       type이 없으면 잘못된 타입의 값이 전달되어도 오류를 잡지 못합니다.

variable "name" {
  type        = string
  description = "리소스 네이밍 prefix로 사용되는 환경 식별자 (예: dev, prod, staging)"
  # default를 설정하지 않은 이유: 필수값으로 강제합니다.
  # 모듈 호출자가 반드시 명시하도록 하여 실수로 잘못된 환경에 배포되는 것을 방지합니다.
}

variable "cidr" {
  type        = string
  description = "VPC CIDR 블록. /16 권장 — 서브넷을 최대 256개까지 생성할 수 있는 여유 공간 확보 (예: 10.0.0.0/16)"
  # default를 설정하지 않은 이유: CIDR은 환경마다 달라야 하는 필수값입니다.
  # 실수로 CIDR이 겹치면 VPC Peering이나 Transit Gateway 연결이 불가능해집니다.
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그 맵. 비용 추적, 환경 식별, 자원 관리에 사용됩니다 (예: {Environment = 'dev', Project = 'my-app'})"
  default     = {}
  # default = {}: tags는 선택적이므로 빈 맵을 기본값으로 설정합니다.
  # 호출부에서 tags를 전달하면 main.tf의 merge()를 통해 Name 태그와 합산됩니다.
}


variable "public_subnet_cidrs" {
  type        = map(string)
  description = "Public Subnet { AZ => CIDR } 맵. for_each의 키가 AZ 이름이 되어 순서 변경에 안전하다 (예: {\"ap-northeast-2a\" = \"10.0.1.0/24\"})"
}

variable "private_nat_subnet_cidrs" {
  type        = map(string)
  description = "Private NAT Subnet { AZ => CIDR } 맵. NAT Gateway를 통해 아웃바운드 인터넷만 허용하는 App 서버용 서브넷 (예: {\"ap-northeast-2a\" = \"10.0.11.0/24\"})"
}

variable "private_full_subnet_cidrs" {
  type        = map(string)
  description = "Private Full Subnet { AZ => CIDR } 맵. 인터넷 접근이 완전히 차단된 DB 전용 서브넷. VPC 내부 통신만 허용 (예: {\"ap-northeast-2a\" = \"10.0.21.0/24\"})"
}