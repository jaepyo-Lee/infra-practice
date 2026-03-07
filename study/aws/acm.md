# ACM (AWS Certificate Manager)

> 마지막 업데이트: 2026-03-07 (DNS 레코드 타입 섹션 추가)

---

## 1. 개념 설명

### ACM이란

HTTPS를 쓰려면 SSL/TLS 인증서가 필요하다. ACM은 이 인증서를 **무료로 발급·갱신·관리**해주는 서비스다.

- 발급: 무료
- 갱신: 만료 전 자동 갱신 (인증서 만료로 인한 장애 방지)
- 설치: AWS 서비스(ALB, CloudFront)에 자동 연결

### 인증 방식

| 방식 | 방법 | 특징 |
|------|------|------|
| **DNS 검증** | Route53에 CNAME 레코드 추가 | 자동 갱신 가능. Terraform 자동화에 적합 |
| **이메일 검증** | 도메인 관리자 이메일로 승인 | 수동 작업 필요. 자동화 불가 |

Terraform 자동화 시 반드시 **DNS 검증**을 써야 한다.

### 중요: ACM 인증서는 리전에 종속된다

| 용도 | 발급 리전 | 이유 |
|------|----------|------|
| ALB | `ap-northeast-2` (서울) | ALB가 서울 리전에 있으므로 |
| **CloudFront** | **`us-east-1` (버지니아)** | CloudFront가 글로벌 서비스라 버지니아에서만 인증서를 읽음 |

Terraform에서 `provider alias`로 두 리전을 동시에 다뤄야 한다.

### 3-Tier 아키텍처에서의 위치

```
사용자
  ↓ HTTPS
CloudFront ← ACM (us-east-1 인증서)
  ↓ HTTPS
ALB ← ACM (ap-northeast-2 인증서)
  ↓ HTTP (내부망)
App EC2
```

---

## 2. Terraform 핵심 파라미터

### `aws_acm_certificate`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `domain_name` | ✅ | 인증서를 발급할 도메인 (`example.com`) |
| `validation_method` | ✅ | `"DNS"` 또는 `"EMAIL"`. Terraform 자동화 시 반드시 `"DNS"` |
| `subject_alternative_names` | 선택 | 추가 도메인 목록. `["*.example.com"]` |
| `provider` | CloudFront용 시 필수 | `aws.us_east_1` alias 지정 |

`subject_alternative_names`에 `*.example.com`(와일드카드)를 추가하면 하나의 인증서로 모든 서브도메인을 커버할 수 있다.

### `aws_acm_certificate_validation`

DNS 검증 완료를 Terraform이 기다리게 만드는 리소스. 없으면 인증서가 검증되기 전에 ALB에 붙이려다 에러가 난다.

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `certificate_arn` | ✅ | 검증 대기할 인증서 ARN |
| `validation_record_fqdns` | ✅ | Route53에 생성한 DNS 검증 레코드 FQDN 목록 |

### CloudFront용 인증서 — provider alias 필수

```hcl
# root module에 us-east-1 provider 별칭 선언
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# CloudFront용 인증서
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = "example.com"
  validation_method = "DNS"
}
```

### DNS 검증 전체 흐름

```
aws_acm_certificate
  → domain_validation_options (CNAME 레코드 정보 제공)
    → aws_route53_record (CNAME 레코드 생성)
      → aws_acm_certificate_validation (검증 완료 대기)
        → ALB listener에 인증서 ARN 사용
```

---

## 3. 이 프로젝트에서의 위치

**Phase 2 — Security Layer** (인증서 발급)
**Phase 3 — Web Tier** (ALB, CloudFront에 연결)

의존 관계:
```
[선행] Route53 Hosted Zone (도메인 보유 필요)
    → [현재] ACM 인증서 발급 + DNS 검증
    → [후행] ALB HTTPS listener, CloudFront distribution
```

구현할 리소스:
1. `aws_acm_certificate` — ALB용 (ap-northeast-2)
2. `aws_acm_certificate` — CloudFront용 (us-east-1, provider alias)
3. `aws_route53_record` — DNS 검증 레코드
4. `aws_acm_certificate_validation` — 검증 완료 대기

→ [핵심 블록 & for_each](../terraform/core-blocks.md)
→ [모듈 구조 컨벤션 (provider alias)](../terraform/module-structure.md)

---

## 4. DNS 레코드 타입

ACM과 Route53을 같이 쓸 때 레코드 타입을 명확히 알아야 한다.

### 레코드 타입 전체

| 타입 | 용도 | 값 형태 |
|------|------|---------|
| **A** | 도메인 → IPv4 주소 | `1.2.3.4` |
| **AAAA** | 도메인 → IPv6 주소 | `2001:db8::1` |
| **CNAME** | 도메인 → 다른 도메인 (별칭) | `my-alb.ap-northeast-2.elb.amazonaws.com` |
| **Alias** | AWS 전용 A레코드 확장. Zone Apex에서도 사용 가능 | ALB, CloudFront DNS |
| **TXT** | 텍스트 저장. 도메인 소유권 증명 등 | `"v=spf1 ..."` |
| **MX** | 메일 서버 지정 | `10 mail.example.com` |
| **NS** | 이 도메인을 관리하는 네임서버 | `ns-123.awsdns-45.com` |

### 이 프로젝트에서 실제로 쓰는 레코드

**① ACM DNS 검증 — CNAME**
ACM이 발급 시 제공하는 검증용 CNAME. Route53에 추가해서 도메인 소유권을 증명한다.

```
이름: _abc123.example.com  (ACM이 지정)
타입: CNAME
값:   _xyz789.acm-validations.aws.  (ACM이 지정)
```

Terraform에서는 `aws_acm_certificate.domain_validation_options`에서 이 정보를 자동으로 가져와 Route53 레코드를 생성한다.

**② CloudFront 연결 — Alias A 레코드**
```
이름: example.com  (Zone Apex)
타입: A (Alias)
값:   d123.cloudfront.net
```

**③ ALB 연결 — Alias A 레코드**
```
이름: api.example.com
타입: A (Alias)
값:   my-alb.ap-northeast-2.elb.amazonaws.com
```

### CNAME vs Alias — 반드시 구분해야 하는 이유

| | CNAME | Alias |
|--|-------|-------|
| Zone Apex(`example.com`) 사용 | ❌ DNS 표준상 불가 | ✅ 가능 |
| 비용 | 쿼리당 과금 | **무료** (Route53 내부 처리) |
| 대상 | 모든 도메인 | AWS 리소스만 (ALB, CloudFront, S3 등) |

**Zone Apex**: `example.com`처럼 앞에 서브도메인이 없는 최상위 도메인.
DNS 표준상 Zone Apex에는 CNAME을 쓸 수 없다. `example.com` → ALB/CloudFront 연결 시 반드시 **Alias**를 써야 한다.
`www.example.com`처럼 서브도메인이 있으면 CNAME도 가능하지만, Alias가 무료이므로 Alias를 권장한다.

### Terraform에서 CNAME vs Alias 작성 차이

**CNAME** — `records`와 `ttl` 사용:
```hcl
resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_abc123.example.com"
  type    = "CNAME"
  ttl     = 60
  records = ["_xyz789.acm-validations.aws."]
}
```

**Alias A** — `alias {}` 블록 사용 (records/ttl 없음):
```hcl
resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
```

Alias는 `records`/`ttl` 대신 `alias {}` 블록을 쓰는 것이 핵심 차이다.