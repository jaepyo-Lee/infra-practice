output "alb_arn" {
  value       = aws_lb.alb.arn
  description = "ALB ARN. CloudFront Origin 설정에 사용."
}

output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
  description = "ALB DNS 이름. Route53 Alias 레코드 타겟에 사용."
}

output "alb_zone_id" {
  value       = aws_lb.alb.zone_id
  description = "ALB Hosted Zone ID. Route53 Alias 레코드 설정에 필요."
}

output "target_group_arn" {
  value       = aws_lb_target_group.app.arn
  description = "Target Group ARN. Phase 4 ASG가 이 TG에 등록됨."
}

output "cloudfront_domain_name" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
  description = "xxx.cloudfront.net. Route53 Alias 타겟에 사용. enable_cloudfront = false면 null"
}

output "cloudfront_distribution_id" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].id : null
  description = "WAF 연결 및 Cache Invalidation에 사용. enable_cloudfront = false면 null"
}
