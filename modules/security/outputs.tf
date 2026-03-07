# Security Group IDs
output "sg_ids" {
  value       = { for k, v in aws_security_group.sg : k => v.id }
  description = "Security Group ID 맵 { key => SG ID }. 예: sg_ids[\"alb_sg\"]"
}

# ACM 인증서 ARN
output "acm_regional_arns" {
  value       = { for k, v in aws_acm_certificate.regional : k => v.arn }
  description = "ALB용 ACM 인증서 ARN 맵 { key => ARN }. ap-northeast-2 리전."
}

output "acm_global_arns" {
  value       = { for k, v in aws_acm_certificate.global : k => v.arn }
  description = "CloudFront용 ACM 인증서 ARN 맵 { key => ARN }. us-east-1 리전."
}

# IAM Instance Profile
output "iam_instance_profile_arns" {
  value       = { for k, v in aws_iam_instance_profile.profiles : k => v.arn }
  description = "IAM Instance Profile ARN 맵 { key => ARN }. ASG Launch Template에 연결."
}
