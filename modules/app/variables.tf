variable "name" {
  type        = string
  description = "리소스 네이밍 prefix (예: dev, prod)"
}

variable "instance_type" {
  type        = string
  description = "EC2 인스턴스 타입. dev는 t3.micro, prod는 t3.small 이상 권장"
  default     = "t3.micro"
}

variable "volume_size" {
  type        = number
  description = "루트 EBS 볼륨 크기(GB). 기본 20GB"
  default     = 20
}

variable "app_port" {
  type        = number
  description = "앱 서버가 수신할 포트. ALB Target Group 포트와 일치해야 함"
  default     = 8080
}

variable "min_size" {
  type        = number
  description = "ASG 최소 인스턴스 수. HA를 위해 최소 1 이상 유지"
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

variable "vpc_id" {
  type        = string
  description = "VPC ID. network 레이어 outputs에서 참조"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ASG가 인스턴스를 배치할 Private NAT 서브넷 ID 목록 (Multi-AZ)"
}

variable "security_group_id" {
  type        = string
  description = "App 서버에 적용할 Security Group ID (app_sg)"
}

variable "target_group_arn" {
  type        = string
  description = "ALB Target Group ARN. ASG가 인스턴스를 여기에 자동 등록함"
}

variable "iam_instance_profile_arn" {
  type        = string
  description = "EC2 IAM Instance Profile ARN. SSM, CloudWatch, Secrets Manager 접근에 필요"
}

variable "tags" {
  type        = map(string)
  description = "공통 태그 맵. 리소스 네이밍 및 비용 추적에 활용"
  default     = {}
}
