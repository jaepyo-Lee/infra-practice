terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = var.tags
  }
}

module "monitoring" {
  source = "../../../modules/monitoring"

  name        = var.name
  alarm_email = var.alarm_email

  # ── web 레이어에서 가져오는 값 ──────────────────────────────
  # modules/monitoring/main.tf 내부 locals에서 arn_suffix를 자동 추출
  alb_arn          = data.terraform_remote_state.web.outputs.alb_arn
  target_group_arn = data.terraform_remote_state.web.outputs.target_group_arn

  # ── app 레이어에서 가져오는 값 ──────────────────────────────
  asg_name = data.terraform_remote_state.app.outputs.asg_name

  # ── database 레이어에서 가져오는 값 ─────────────────────────
  rds_cluster_id             = data.terraform_remote_state.database.outputs.rds_cluster_id
  redis_replication_group_id = data.terraform_remote_state.database.outputs.redis_replication_group_id

  # ── 알람 임계값 (변수로 환경별 조정 가능) ────────────────────
  alb_5xx_threshold           = var.alb_5xx_threshold
  alb_response_time_threshold = var.alb_response_time_threshold
  asg_cpu_threshold           = var.asg_cpu_threshold
  rds_cpu_threshold           = var.rds_cpu_threshold
  rds_connections_threshold   = var.rds_connections_threshold
  redis_memory_threshold      = var.redis_memory_threshold

  # ── 로그 보존 기간 ───────────────────────────────────────────
  log_retention_days            = var.log_retention_days
  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  tags = var.tags
}
