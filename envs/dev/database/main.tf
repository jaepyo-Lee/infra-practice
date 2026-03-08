terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # random provider: modules/database/main.tf의 random_password가 사용
    # modules 내부에서 random을 쓰면 envs 레벨에서도 선언이 필요함
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = var.tags
    # default_tags: 이 provider로 생성되는 모든 리소스에 공통 태그 자동 적용
    # RDS, ElastiCache, SG 등 모든 리소스에 Environment, ManagedBy 태그가 붙음
  }
}

module "database" {
  source = "../../../modules/database"

  name = var.name

  # ── network 레이어에서 가져오는 값 ──────────────────────────────
  vpc_id        = data.terraform_remote_state.network.outputs.vpc_id
  # private_full_subnet_ids: 인터넷 아웃바운드 없는 완전 격리 서브넷
  # NAT GW도 없음 → RDS/Redis가 외부 인터넷에 데이터를 보낼 방법이 없어 보안 강화
  db_subnet_ids = data.terraform_remote_state.network.outputs.private_full_subnet_ids

  # ── security 레이어에서 가져오는 값 ─────────────────────────────
  # db_sg: App SG → DB SG:3306 인바운드 허용 (이미 security 레이어에서 설정됨)
  db_sg_id  = data.terraform_remote_state.security.outputs.sg_ids["db_sg"]
  # app_sg: cache_sg의 ingress source로 사용 → App 서버에서만 Redis 6379 허용
  app_sg_id = data.terraform_remote_state.security.outputs.sg_ids["app_sg"]

  # ── RDS 설정 ──────────────────────────────────────────────────
  db_name            = var.db_name
  db_master_username = var.db_master_username

  aurora_instance_class = var.aurora_instance_class
  aurora_instance_count = var.aurora_instance_count

  backup_retention_period     = var.backup_retention_period
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  secret_recovery_window_days = var.secret_recovery_window_days

  # ── ElastiCache 설정 ───────────────────────────────────────────
  redis_node_type                = var.redis_node_type
  redis_num_cache_clusters       = var.redis_num_cache_clusters
  redis_snapshot_retention_limit = var.redis_snapshot_retention_limit

  tags = var.tags
}
