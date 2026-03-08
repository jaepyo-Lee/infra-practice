# modules/monitoring/main.tf
# Phase 6 — Observability
# CloudWatch Alarms, SNS, CloudTrail, Log Groups, Dashboard, S3(ALB Access Log)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 공통 데이터 소스
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ELB 서비스 계정: ALB가 S3에 로그를 쓰기 위해 필요한 AWS 관리 계정
# 리전마다 다른 고정 계정 ID를 AWS가 관리함 — 직접 하드코딩하면 안 됨
data "aws_elb_service_account" "main" {}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# locals — ARN suffix 추출
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CloudWatch 메트릭 Dimension에는 전체 ARN이 아닌 suffix만 사용
#
# ALB ARN 예시:
#   arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/dev-alb/abc123
# → suffix: app/dev-alb/abc123
#
# Target Group ARN 예시:
#   arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/dev-app-tg/abc123
# → suffix: targetgroup/dev-app-tg/abc123
locals {
  alb_arn_suffix = regex("loadbalancer/(.*)", var.alb_arn)[0]
  tg_arn_suffix  = regex(":(targetgroup/.*)", var.target_group_arn)[0]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. SNS 토픽 — 알림 허브
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SNS (Simple Notification Service): 발행-구독(Pub/Sub) 패턴의 메시지 버스
# CloudWatch Alarm이 이 토픽에 메시지를 발행 → 구독자(이메일, Lambda, Slack 등)에게 전달
# 여러 알람이 하나의 토픽을 공유 → 구독 관리가 중앙화됨
resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarm-topic"

  tags = merge(var.tags, { Name = "${var.name}-alarm-topic" })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
  # ⚠️ 최초 생성 시 AWS가 확인 이메일을 발송함
  # 수신자가 "Confirm subscription" 클릭 전까지 알림이 전달되지 않음
  # → terraform apply 후 이메일 확인 필수
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. CloudWatch Log Groups
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RDS가 enabled_cloudwatch_logs_exports로 자동 생성하는 로그 그룹을
# 명시적으로 선언해 retention_in_days를 제어함
#
# ⚠️ 로그 그룹 이름이 AWS 자동 생성 경로와 정확히 일치해야 함
#    이름이 다르면 RDS가 새 로그 그룹을 retention 없이 자동 생성해버림
locals {
  rds_log_types = ["audit", "error", "slowquery"]
}

resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(local.rds_log_types)

  name              = "/aws/rds/cluster/${var.rds_cluster_id}/${each.key}"
  retention_in_days = var.log_retention_days
  # retention_in_days: 지정 기간 이후 로그 자동 삭제
  # 0 = 영구 보존 (비용 무한 증가 위험)

  tags = merge(var.tags, { Name = "/aws/rds/cluster/${var.rds_cluster_id}/${each.key}" })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/app"
  retention_in_days = var.log_retention_days
  # App 서버의 애플리케이션 로그를 수집하는 그룹
  # EC2에 CloudWatch Agent를 설치하면 이 그룹으로 로그를 전송 가능
  # → ssm-agent 또는 User Data로 Agent 설치 후 config.json에서 log_group_name 지정

  tags = merge(var.tags, { Name = "/${var.name}/app" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. CloudWatch Alarms — ALB
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 네임스페이스: AWS/ApplicationELB
# Dimension: LoadBalancer (arn_suffix), TargetGroup (arn_suffix)
#
# evaluation_periods: 연속으로 몇 번 임계값을 초과해야 알람을 울릴지
# → 순간 스파이크에 의한 오탐(false alarm) 방지

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name        = "${var.name}-alb-5xx-errors"
  alarm_description = "ALB 5xx 에러가 ${var.alb_5xx_threshold}개를 초과했습니다. 백엔드 서버 이상 가능성"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"
  # treat_missing_data=notBreaching: 데이터가 없으면 정상으로 간주
  # 트래픽이 없는 새벽에 알람이 오는 현상 방지

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  # ok_actions: 알람 → 정상 복구 시에도 알림 발송
  # "장애가 언제 해소됐는지" 추적 가능

  tags = merge(var.tags, { Name = "${var.name}-alb-5xx-errors" })
}

resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name        = "${var.name}-alb-response-time"
  alarm_description = "ALB 평균 응답 시간이 ${var.alb_response_time_threshold}초를 초과했습니다. 백엔드 성능 저하 가능성"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = local.tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-alb-response-time" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. CloudWatch Alarms — EC2 / ASG
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 네임스페이스: AWS/EC2
# Dimension: AutoScalingGroupName
#
# ASG Scaling Policy의 CPU 기반 Target Tracking과 역할이 다름:
# - Scaling Policy: 인스턴스 수를 조정 (자동화)
# - CloudWatch Alarm: 지속적 고CPU 상태를 운영팀에 알림 (가시성)
resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name        = "${var.name}-asg-cpu-high"
  alarm_description = "ASG 평균 CPU가 ${var.asg_cpu_threshold}%를 초과했습니다. 스케일 아웃 부족 또는 앱 이상 확인 필요"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.asg_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-asg-cpu-high" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. CloudWatch Alarms — RDS Aurora
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 네임스페이스: AWS/RDS
# Dimension: DBClusterIdentifier (클러스터 단위 메트릭)
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name        = "${var.name}-rds-cpu-high"
  alarm_description = "RDS Aurora CPU가 ${var.rds_cpu_threshold}%를 초과했습니다. 느린 쿼리 분석 또는 인스턴스 업그레이드 검토"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.rds_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-rds-cpu-high" })
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name        = "${var.name}-rds-connections-high"
  alarm_description = "RDS 동시 연결 수가 ${var.rds_connections_threshold}를 초과했습니다. Connection Pool 설정 확인 또는 인스턴스 업그레이드 검토"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.rds_connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.rds_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-rds-connections-high" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. CloudWatch Alarms — ElastiCache Redis
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 네임스페이스: AWS/ElastiCache
# Dimension: ReplicationGroupId
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name        = "${var.name}-redis-memory-high"
  alarm_description = "Redis 메모리 사용률이 ${var.redis_memory_threshold}%를 초과했습니다. Eviction(데이터 강제 삭제) 발생 위험"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = var.redis_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.redis_replication_group_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-redis-memory-high" })
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name        = "${var.name}-redis-cpu-high"
  alarm_description = "Redis 엔진 CPU가 50%를 초과했습니다. Redis는 단일 스레드 — CPU 병목은 심각한 지연을 유발함"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  # EngineCPUUtilization: Redis 엔진 자체의 CPU 사용률
  # 일반 CPUUtilization과 다름 — Redis 특화 메트릭
  # Redis는 단일 스레드: 20% 초과 시 지연 시작, 50% 이상이면 심각
  namespace          = "AWS/ElastiCache"
  period             = 60
  statistic          = "Average"
  threshold          = 50
  treat_missing_data = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.redis_replication_group_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, { Name = "${var.name}-redis-cpu-high" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. S3 — ALB Access Log 저장소
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ALB Access Log: 모든 HTTP 요청의 상세 기록 (IP, 응답시간, 상태코드, 요청 URI 등)
# CloudWatch Metrics와 달리 개별 요청 단위로 분석 가능
# → 특정 IP의 요청 패턴 분석, 느린 요청 추적, 보안 감사에 활용
#
# ⚠️ ALB에서 access_logs 블록 설정이 필요
#    이 버킷만 만들어도 ALB 설정을 변경하기 전까지 로그는 쌓이지 않음
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name}-alb-access-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.tags, { Name = "${var.name}-alb-access-logs" })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb-logs-retention"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  # public_access_block이 완전히 적용된 후 policy를 붙여야 충돌 없음
  depends_on = [aws_s3_bucket_public_access_block.alb_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ALB 서비스 계정에게 이 버킷에 로그를 PUT할 권한 부여
        # data.aws_elb_service_account.main: 리전별 ELB 서비스 계정 ARN을 자동 조회
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. CloudTrail — API 감사 로그
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CloudTrail: AWS 계정의 모든 API 호출을 기록
# "누가(Who), 언제(When), 어디서(Where), 무엇을(What)" 했는지 추적
# 보안 침해 사고 조사, 컴플라이언스(SOC2, ISO27001, PCI-DSS) 필수 요소
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.name}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  # force_destroy=true: terraform destroy 시 로그가 있어도 버킷 삭제 허용 (dev용)
  # prod 환경에서는 false로 설정 — 감사 로그는 영구 보존이 원칙

  tags = merge(var.tags, { Name = "${var.name}-cloudtrail-logs" })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  # 감사 로그를 퍼블릭에 노출하면 보안 위반 — 4가지 모두 true 필수
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"

    expiration {
      days = var.cloudtrail_log_retention_days
      # 규정에 따라 1년~5년 보존 후 Glacier로 이전하는 패턴도 있음
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.cloudtrail.id
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudTrail이 S3에 로그를 쓰려면 먼저 버킷 ACL 확인 권한이 필요
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        # 실제 로그 파일 PUT 권한
        # Condition으로 이 계정의 CloudTrail만 허용 (다른 계정 차단)
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name           = "${var.name}-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id
  depends_on     = [aws_s3_bucket_policy.cloudtrail]
  # depends_on 필수: S3 bucket policy가 없으면 CloudTrail 생성 시 권한 오류 발생

  include_global_service_events = true
  # true: IAM, STS, Route53 등 글로벌 서비스 이벤트도 기록
  # false로 하면 IAM 변경 사항이 누락됨 — 보안 감사에서 치명적

  is_multi_region_trail = false
  # false: 현재 리전만 기록 (비용 절감, dev용)
  # prod에서는 true로 설정해 모든 리전의 API 호출을 추적

  enable_log_file_validation = true
  # 로그 파일 해시(SHA-256) 생성 → 파일 변조 여부 검증 가능
  # 보안 감사(Forensics)에서 로그 무결성 증명에 필수

  tags = merge(var.tags, { Name = "${var.name}-cloudtrail" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. CloudWatch Dashboard
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard: 여러 서비스의 메트릭을 한 화면에서 시각화
# JSON으로 위젯 배치를 정의 — x, y, width, height로 그리드 위치 지정
# 24컬럼 그리드 시스템 사용
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name}-overview"

  dashboard_body = jsonencode({
    widgets = [

      # ── 행 1: ALB ────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB — 요청 수 & 5xx 에러"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_arn_suffix,
            { stat = "Sum", label = "총 요청 수" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_arn_suffix,
            { stat = "Sum", label = "5xx 에러", color = "#d62728" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB — 응답 시간 (초)"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix,
            { stat = "Average", label = "평균 응답시간" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix,
            { stat = "p99", label = "p99 응답시간", color = "#ff7f0e" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      },

      # ── 행 2: EC2 & RDS ─────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EC2 ASG — CPU 사용률 (%)"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name,
            { stat = "Average", label = "평균 CPU" }]
          ]
          view   = "timeSeries"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.asg_cpu_threshold, label = "알람 임계값", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS Aurora — CPU & 연결 수"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", var.rds_cluster_id,
            { stat = "Average", label = "CPU (%)" }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", var.rds_cluster_id,
            { stat = "Average", label = "연결 수", yAxis = "right" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      },

      # ── 행 3: Redis ──────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Redis — 메모리 사용률 (%)"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", var.redis_replication_group_id,
            { stat = "Average", label = "메모리 사용률" }]
          ]
          view   = "timeSeries"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.redis_memory_threshold, label = "알람 임계값", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Redis — 캐시 히트율"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ElastiCache", "CacheHits", "ReplicationGroupId", var.redis_replication_group_id,
            { stat = "Sum", label = "Cache Hits" }],
            ["AWS/ElastiCache", "CacheMisses", "ReplicationGroupId", var.redis_replication_group_id,
            { stat = "Sum", label = "Cache Misses", color = "#d62728" }]
          ]
          # 히트율 = CacheHits / (CacheHits + CacheMisses)
          # 히트율이 낮으면 캐시 워밍업 부족 또는 TTL 설정 문제
          view   = "timeSeries"
          period = 60
        }
      }
    ]
  })
}
