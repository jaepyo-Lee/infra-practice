output "sg_ids" {
  value       = module.security_group.sg_ids
  description = "Security Group ID 맵 { key => SG ID }"
}

output "acm_regional_arns" {
  value       = module.security_group.acm_regional_arns
  description = "ALB용 ACM 인증서 ARN 맵 (ap-northeast-2)"
}

output "acm_global_arns" {
  value       = module.security_group.acm_global_arns
  description = "CloudFront용 ACM 인증서 ARN 맵 (us-east-1)"
}

output "iam_instance_profile_arns" {
  value       = module.security_group.iam_instance_profile_arns
  description = "IAM Instance Profile ARN 맵"
}
