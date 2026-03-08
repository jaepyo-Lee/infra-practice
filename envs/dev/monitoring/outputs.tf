output "sns_topic_arn" {
  value       = module.monitoring.sns_topic_arn
  description = "알람 SNS 토픽 ARN"
}

output "app_log_group_name" {
  value       = module.monitoring.app_log_group_name
  description = "App 로그 그룹 이름. EC2 CloudWatch Agent 설정에서 사용"
}

output "alb_logs_bucket_name" {
  value       = module.monitoring.alb_logs_bucket_name
  description = "ALB Access Log S3 버킷 이름. ALB access_logs 설정 시 사용"
}

output "dashboard_name" {
  value       = module.monitoring.dashboard_name
  description = "CloudWatch 대시보드 이름. AWS 콘솔 → CloudWatch → Dashboards에서 확인"
}

output "cloudtrail_arn" {
  value       = module.monitoring.cloudtrail_arn
  description = "CloudTrail ARN"
}
