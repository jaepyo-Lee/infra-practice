variable "name" {
  type        = string
  description = "환경 이름. 리소스 네이밍 prefix로 사용됨 (예: dev, prod)"
}

variable "alarm_email" {
  type        = string
  description = "CloudWatch 알람 수신 이메일. SNS 구독 확인 메일이 발송됨 — apply 후 반드시 확인 클릭 필요"
}

# ── ALB ─────────────────────────────────────────────────────

variable "alb_arn" {
  type        = string
  description = "ALB 전체 ARN. monitoring 모듈 내부에서 CloudWatch Dimension용 suffix를 추출함"
}

variable "target_group_arn" {
  type        = string
  description = "Target Group 전체 ARN. monitoring 모듈 내부에서 CloudWatch Dimension용 suffix를 추출함"
}

# ── ASG ─────────────────────────────────────────────────────

variable "asg_name" {
  type        = string
  description = "Auto Scaling Group 이름. CloudWatch 메트릭 Dimension에 사용"
}

# ── RDS ─────────────────────────────────────────────────────

variable "rds_cluster_id" {
  type        = string
  description = "Aurora 클러스터 ID. CloudWatch 메트릭 Dimension 및 로그 그룹 이름 결정에 사용"
}

# ── ElastiCache ──────────────────────────────────────────────

variable "redis_replication_group_id" {
  type        = string
  description = "Redis Replication Group ID. CloudWatch 메트릭 Dimension에 사용"
}

# ── 알람 임계값 ──────────────────────────────────────────────

variable "alb_5xx_threshold" {
  type        = number
  description = "ALB 5xx 에러 개수 알람 임계값. 이 값을 초과하면 SNS 알림 발송"
  default     = 10
}

variable "alb_response_time_threshold" {
  type        = number
  description = "ALB 평균 응답 시간 알람 임계값 (초). 초과 시 백엔드 성능 저하 의심"
  default     = 2
}

variable "asg_cpu_threshold" {
  type        = number
  description = "EC2 ASG 평균 CPU 알람 임계값 (%). Scaling Policy와 별개 — 지속적 고CPU 감지용"
  default     = 80
}

variable "rds_cpu_threshold" {
  type        = number
  description = "RDS Aurora CPU 알람 임계값 (%). 지속적으로 높으면 인스턴스 업그레이드 또는 쿼리 최적화 필요"
  default     = 80
}

variable "rds_connections_threshold" {
  type        = number
  description = "RDS 동시 연결 수 알람 임계값. db.t3.medium 최대: 약 90. 초과 시 연결 거부됨"
  default     = 80
}

variable "redis_memory_threshold" {
  type        = number
  description = "Redis 메모리 사용률 알람 임계값 (%). 80% 초과 시 Eviction(데이터 강제 삭제) 위험"
  default     = 80
}

# ── 로그 보존 ────────────────────────────────────────────────

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs 보존 기간 (일). 이후 자동 삭제. 0=영구 보존(비용 무한 증가 주의)"
  default     = 30
}

variable "cloudtrail_log_retention_days" {
  type        = number
  description = "CloudTrail 로그의 S3 보존 기간 (일). 규정 준수상 최소 90일 이상 권장"
  default     = 90
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그"
  default     = {}
}
