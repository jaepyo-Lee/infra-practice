# CloudFront용 WAF는 반드시 us-east-1에 생성해야 한다
# 호출자(envs/dev/web/main.tf)에서 providers 블록으로 aws.us_east_1을 전달해야 함
resource "aws_wafv2_web_acl" "main" {
  count    = var.enable_waf ? 1 : 0
  provider = aws.us_east_1

  name  = "${var.name}-waf"
  scope = "CLOUDFRONT"

  # Rule에 매칭되지 않은 요청은 기본 허용
  # 차단 목록(블랙리스트) 방식 — 명시적으로 막은 것만 차단
  default_action {
    allow {}
  }

  # OWASP Top 10 기본 방어 (SQL Injection, XSS 등)
  # Managed Rule Group은 action 대신 override_action을 사용
  # → Rule Group 내부에 이미 action이 정의되어 있으므로 그대로 따름(none)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common-rule"
      sampled_requests_enabled   = true
    }
  }

  # WAF 전체 메트릭 설정 (필수 블록)
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Name = "${var.name}-waf" })
}
