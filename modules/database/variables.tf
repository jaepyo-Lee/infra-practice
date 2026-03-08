variable "name" {
  type        = string
  description = "리소스 네이밍 prefix (예: dev, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID. network 레이어 outputs.vpc_id에서 참조"
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "DB 서브넷 ID 목록. private_full_subnet_ids (NAT 없는 완전 격리 서브넷) 사용"
}

variable "db_sg_id" {
  type        = string
  description = "RDS용 Security Group ID (db_sg). security 레이어 outputs.sg_ids[\"db_sg\"]에서 참조"
}

variable "app_sg_id" {
  type        = string
  description = "App 서버 SG ID (app_sg). cache_sg의 ingress source로 사용"
}

# ── RDS 설정 ─────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "생성할 초기 데이터베이스 이름"
  default     = "appdb"
}

variable "db_master_username" {
  type        = string
  description = "RDS 마스터 사용자 이름. 'admin', 'root' 등 예약어는 사용 불가"
  default     = "dbadmin"
}

variable "aurora_instance_class" {
  type        = string
  description = "Aurora 인스턴스 타입. 최소: db.t3.medium (db.t3.micro는 Aurora 미지원)"
  default     = "db.t3.medium"
}

variable "aurora_instance_count" {
  type        = number
  description = "Aurora 인스턴스 수. 1=Writer만(HA 없음), 2=Writer+Reader(HA 구성)"
  default     = 2
}

variable "backup_retention_period" {
  type        = number
  description = "자동 백업 보존 기간(일). 범위: 1-35. 0은 자동 백업 비활성화. dev=1, prod=7 이상 권장"
  default     = 1
}

variable "deletion_protection" {
  type        = bool
  description = "RDS 삭제 보호. true이면 Terraform destroy도 불가. dev=false, prod=true 필수"
  default     = false
}

variable "skip_final_snapshot" {
  type        = bool
  description = "클러스터 삭제 시 최종 스냅샷 생략. dev=true, prod=false 필수"
  default     = true
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Secrets Manager 삭제 유예 기간(일). 0=즉시 삭제(dev용), 7-30=복구 가능 기간(prod용)"
  default     = 0
}

# ── ElastiCache 설정 ──────────────────────────────────────────

variable "redis_node_type" {
  type        = string
  description = "Redis 노드 타입. dev: cache.t3.micro(0.5GB), prod: cache.r6g.large(13GB) 이상 권장"
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  type        = number
  description = "Redis 노드 수 (Primary 포함). automatic_failover 활성화 위해 최소 2 필요"
  default     = 2
}

variable "redis_snapshot_retention_limit" {
  type        = number
  description = "Redis 자동 스냅샷 보존 일수. 0=비활성화, dev=1, prod=7 이상 권장"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "공통 태그 맵. 리소스 식별 및 비용 추적에 활용"
  default     = {}
}