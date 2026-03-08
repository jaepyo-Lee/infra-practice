# ── SNS ──────────────────────────────────────────────────────

output "sns_topic_arn" {
  value       = aws_sns_topic.alarms.arn
  description = "알람 SNS 토픽 ARN. 추가 알람 또는 Lambda 트리거 연결 시 참조"
}

# ── CloudWatch Log Groups ─────────────────────────────────────

output "rds_log_group_names" {
  value       = { for k, v in aws_cloudwatch_log_group.rds : k => v.name }
  description = "RDS 로그 그룹 이름 맵. {audit, error, slowquery} → 로그 그룹 이름"
}

output "app_log_group_name" {
  value       = aws_cloudwatch_log_group.app.name
  description = "App 서버 로그 그룹 이름. EC2 CloudWatch Agent 설정에서 log_group_name으로 사용"
}

# ── S3 버킷 ───────────────────────────────────────────────────

output "alb_logs_bucket_name" {
  value       = aws_s3_bucket.alb_logs.id
  description = "ALB Access Log S3 버킷 이름. ALB access_logs 블록에서 bucket 값으로 사용"
}

output "alb_logs_bucket_arn" {
  value       = aws_s3_bucket.alb_logs.arn
  description = "ALB Access Log S3 버킷 ARN"
}

output "cloudtrail_bucket_name" {
  value       = aws_s3_bucket.cloudtrail.id
  description = "CloudTrail 로그 S3 버킷 이름"
}

# ── CloudTrail ────────────────────────────────────────────────

output "cloudtrail_arn" {
  value       = aws_cloudtrail.main.arn
  description = "CloudTrail ARN"
}

# ── CloudWatch Dashboard ──────────────────────────────────────

output "dashboard_name" {
  value       = aws_cloudwatch_dashboard.main.dashboard_name
  description = "CloudWatch 대시보드 이름. AWS 콘솔 → CloudWatch → Dashboards에서 확인"
}
