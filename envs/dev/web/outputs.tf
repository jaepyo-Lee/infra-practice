output "alb_arn" {
  value       = module.alb.alb_arn
  description = "ALB ARN"
}

output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "ALB DNS 이름. Route53 Alias 레코드 타겟에 사용."
}

output "alb_zone_id" {
  value       = module.alb.alb_zone_id
  description = "ALB Hosted Zone ID. Route53 Alias 레코드에 사용."
}

output "target_group_arn" {
  value       = module.alb.target_group_arn
  description = "Target Group ARN. Phase 4 ASG 연결에 사용."
}
