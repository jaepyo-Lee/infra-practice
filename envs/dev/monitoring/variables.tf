variable "name" {
  type        = string
  description = "환경 이름. 리소스 네이밍 prefix로 사용됨"
  default     = "dev"
}

variable "alarm_email" {
  type        = string
  description = "CloudWatch 알람 수신 이메일. apply 후 확인 메일의 'Confirm subscription' 클릭 필수"
  default     = "your-email@example.com"
  # ⚠️ 실제 사용 시 본인 이메일로 변경 필요
}

# ── 알람 임계값 ──────────────────────────────────────────────

variable "alb_5xx_threshold" {
  type        = number
  description = "ALB 5xx 에러 개수 임계값. dev는 낮게 설정해 민감하게 감지"
  default     = 10
}

variable "alb_response_time_threshold" {
  type        = number
  description = "ALB 평균 응답 시간 임계값 (초)"
  default     = 2
}

variable "asg_cpu_threshold" {
  type        = number
  description = "EC2 ASG CPU 임계값 (%). Scaling Policy의 target_value와 별개"
  default     = 80
}

variable "rds_cpu_threshold" {
  type        = number
  description = "RDS Aurora CPU 임계값 (%)"
  default     = 80
}

variable "rds_connections_threshold" {
  type        = number
  description = "RDS 동시 연결 수 임계값. db.t3.medium 최대 연결 수: 약 90"
  default     = 80
}

variable "redis_memory_threshold" {
  type        = number
  description = "Redis 메모리 사용률 임계값 (%). 80% 초과 시 Eviction 위험"
  default     = 80
}

# ── 로그 보존 ────────────────────────────────────────────────

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs 보존 기간 (일). dev는 비용 절감을 위해 짧게 설정"
  default     = 30
}

variable "cloudtrail_log_retention_days" {
  type        = number
  description = "CloudTrail S3 로그 보존 기간 (일). 규정 준수상 90일 이상 권장"
  default     = 90
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그"
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Phase       = "6-monitoring"
  }
}
