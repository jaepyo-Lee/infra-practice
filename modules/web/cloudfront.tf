resource "aws_cloudfront_distribution" "main" {
  count = var.enable_cloudfront ? 1 : 0

  enabled         = true
  price_class     = var.price_class
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "alb"

    # ALB는 S3가 아니므로 custom_origin_config 필수
    custom_origin_config {
      http_port  = 80
      https_port = 443

      # ALB에 ACM 없으므로 HTTP로만 통신
      # CloudFront ↔ 사용자 구간은 viewer_protocol_policy로 HTTPS 강제
      origin_protocol_policy = "http-only"

      # http-only라도 Terraform 필수 인수이므로 명시
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = "alb"

    # 사용자 → CloudFront 구간은 HTTPS 강제
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      # 쿼리스트링을 그대로 ALB에 전달
      query_string = true

      # 모든 헤더를 ALB에 전달 (API 서버 — Host 헤더 등 필요)
      headers = ["*"]

      cookies {
        forward = "all"
      }
    }

    # TTL = 0 → 캐시 비활성화 (동적 API 서버)
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # 지역 제한 없음 (필수 블록 — 없으면 에러)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 도메인 없으므로 CloudFront 기본 인증서 사용 (xxx.cloudfront.net)
  # 커스텀 도메인 연결 시 acm_certificate_arn + ssl_support_method 로 교체
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # 오리진 장애 에러는 캐시하지 않고 즉시 재시도
  # 기본 300초 캐시 → 서버 복구 후에도 5분간 에러 지속되는 문제 방지
  custom_error_response {
    error_code            = 502
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 503
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 504
    error_caching_min_ttl = 0
  }

  tags = merge(var.tags, { Name = "${var.name}-cf" })
}
