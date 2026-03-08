output "asg_name" {
  value       = module.app.asg_name
  description = "ASG 이름. CloudWatch 알람, Scaling Policy 연결에 사용"
}

output "asg_arn" {
  value       = module.app.asg_arn
  description = "ASG ARN"
}

output "launch_template_id" {
  value       = module.app.launch_template_id
  description = "Launch Template ID"
}

output "launch_template_latest_version" {
  value       = module.app.launch_template_latest_version
  description = "Launch Template 최신 버전. Instance Refresh 상태 확인에 사용"
}
