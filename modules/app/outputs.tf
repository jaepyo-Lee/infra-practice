output "asg_name" {
  value       = aws_autoscaling_group.app.name
  description = "ASG 이름. Scaling Policy, CloudWatch 알람 연결에 사용"
}

output "asg_arn" {
  value       = aws_autoscaling_group.app.arn
  description = "ASG ARN"
}

output "launch_template_id" {
  value       = aws_launch_template.app.id
  description = "Launch Template ID. 업데이트 및 버전 관리에 사용"
}

output "launch_template_latest_version" {
  value       = aws_launch_template.app.latest_version
  description = "Launch Template 최신 버전 번호"
}
