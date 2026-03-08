variable "name" {
  type        = string
  description = "환경 이름. 리소스 네이밍 prefix로 사용됨 (예: dev, prod)"
  default     = "dev"
}

# ── RDS 설정 ─────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "Aurora 클러스터에 생성할 초기 데이터베이스 이름"
  default     = "appdb"
}

variable "db_master_username" {
  type        = string
  description = "RDS 마스터 계정 이름. 예약어(admin, root, master 등) 사용 불가"
  default     = "dbadmin"
}

variable "aurora_instance_class" {
  type        = string
  description = "Aurora 인스턴스 타입. db.t3.micro는 Aurora 미지원 — 최소 db.t3.medium 필요"
  default     = "db.t3.medium"
}

variable "aurora_instance_count" {
  type        = number
  description = "Aurora 인스턴스 수. 1=Writer만(비용 절감), 2=Writer+Reader(HA 구성)"
  default     = 2
}

variable "backup_retention_period" {
  type        = number
  description = "자동 백업 보존 기간(일). dev=1로 최소화하여 비용 절감"
  default     = 1
}

variable "deletion_protection" {
  type        = bool
  description = "RDS 삭제 보호. dev 환경에서는 테스트를 위해 false"
  default     = false
}

variable "skip_final_snapshot" {
  type        = bool
  description = "삭제 시 최종 스냅샷 생략. dev=true로 불필요한 스냅샷 방지"
  default     = true
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Secrets Manager 삭제 유예 기간. dev=0으로 즉시 삭제 허용"
  default     = 0
}

# ── ElastiCache 설정 ──────────────────────────────────────────

variable "redis_node_type" {
  type        = string
  description = "Redis 노드 타입. dev: cache.t3.micro (0.5GB, 최소 사양)"
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  type        = number
  description = "Redis 전체 노드 수. 2=Primary+Replica. automatic_failover 활성화 조건"
  default     = 2
}

variable "redis_snapshot_retention_limit" {
  type        = number
  description = "Redis 스냅샷 보존 일수. dev=1로 최소 설정"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그. 비용 대시보드 필터링, 환경 식별에 활용"
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Phase       = "5-database"
  }
}
