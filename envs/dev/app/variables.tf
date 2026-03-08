variable "name" {
  type        = string
  description = "환경 이름. 리소스 네이밍 prefix로 사용됨 (예: dev, prod)"
  default     = "dev"
}

variable "instance_type" {
  type        = string
  description = "EC2 인스턴스 타입. dev는 t3.micro로 비용 절감, prod는 t3.small 이상 권장"
  default     = "t3.micro"
}

variable "min_size" {
  type        = number
  description = "ASG 최소 인스턴스 수. 0이면 HA 불가, 최소 1 권장"
  default     = 1
}

variable "max_size" {
  type        = number
  description = "ASG 최대 인스턴스 수. 비용 상한선 역할"
  default     = 3
}

variable "desired_size" {
  type        = number
  description = "ASG 초기 목표 인스턴스 수. Scaling Policy 실행 후에는 AWS가 관리"
  default     = 1
}

variable "cpu_target_value" {
  type        = number
  description = "CPU Target Tracking 목표값(%). 초과 시 Scale Out, 이하 시 Scale In"
  default     = 60
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그. 비용 대시보드 필터링, 환경 식별에 활용"
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
