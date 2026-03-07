terraform {
  required_providers {
    aws={
      source = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1, aws.ap_northeast_2]
    }
  }
}

# Terraform의 provider 메타 인수는 동적(each.value)으로 설정할 수 없다.
# 따라서 리소스를 두 개로 분리하고, is_global 플래그로 어느 리소스에 넣을지 필터링한다.

# ALB용 ACM — ap-northeast-2 리전 (백엔드 HTTPS 통신)
resource "aws_acm_certificate" "regional" {
  # is_global = false인 항목만 필터링
  for_each = { for k, v in var.acm : k => v if !v.is_global }

  provider                  = aws.ap_northeast_2
  domain_name               = each.value.domain_name
  validation_method         = each.value.validation_method
  subject_alternative_names = each.value.subject_alternative_names
}

# CloudFront용 ACM — us-east-1 리전 (CloudFront는 반드시 us-east-1 ACM만 허용)
resource "aws_acm_certificate" "global" {
  # is_global = true인 항목만 필터링
  for_each = { for k, v in var.acm : k => v if v.is_global }

  provider                  = aws.us_east_1
  domain_name               = each.value.domain_name
  validation_method         = each.value.validation_method
  subject_alternative_names = each.value.subject_alternative_names
}
