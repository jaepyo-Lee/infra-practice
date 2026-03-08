variable "name" {
  type        = string
  description = "리소스 네이밍 prefix (예: dev, prod)"
}

variable "vpc_id" {
  type        = string
  description = "Target Group이 속할 VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ALB를 배치할 Public Subnet ID 목록. 최소 2개 AZ 필수"
}

variable "security_group_id" {
  type        = string
  description = "ALB에 연결할 Security Group ID"
}

variable "certificate_arn" {
  type        = string
  description = "HTTPS 리스너에 연결할 ACM 인증서 ARN (ap-northeast-2). null이면 HTTP만 사용"
  default     = null
}

variable "target_port" {
  type        = number
  description = "EC2 App 서버가 수신하는 포트"
  default     = 8080
}

variable "health_check_path" {
  type        = string
  description = "Target Group 헬스 체크 경로"
  default     = "/health"
}

variable "enable_waf" {
  type        = bool
  description = "WAF Web ACL 생성 여부. true면 us-east-1 provider가 반드시 전달되어야 함"
  default     = true
}

variable "enable_cloudfront" {
  type        = bool
  description = "CloudFront 배포 생성 여부"
  default     = true
}

variable "price_class" {
  type        = string
  description = "CloudFront Price Class. PriceClass_100 / PriceClass_200 / PriceClass_All"
  default     = "PriceClass_200" # 한국 포함
}

variable "tags" {
  type        = map(string)
  description = "공통 태그"
  default     = {}
}
