# CloudFront

> 마지막 업데이트: 2026-03-08
> Phase: Phase 3 — Web Tier

---

## 1. 개념 설명

### CloudFront란

AWS의 **CDN(Content Delivery Network)** 서비스다. 전 세계 엣지 로케이션(450+개)에 콘텐츠를 캐시해서 사용자와 가까운 곳에서 응답한다.

이 프로젝트에서의 역할:

```
인터넷 → CloudFront → ALB → EC2
         (엣지 캐시)   (로드밸런싱)
```

단순 캐시만이 아니라 HTTPS 종료, DDoS 방어, WAF 연결, 글로벌 가속을 담당한다.

---

### 핵심 개념 4가지

**1. Distribution** — CloudFront 배포 단위. 도메인 1개 = Distribution 1개

**2. Origin** — CloudFront가 콘텐츠를 가져오는 원본 서버. ALB, S3, EC2 등

**3. Behavior** — URL 패턴별 캐시 정책. `/api/*`는 캐시 안 하고, `/static/*`는 캐시하는 식으로 분리 가능

**4. Edge Location** — 전 세계에 분산된 캐시 서버. 한국 사용자는 서울 엣지에서 응답받음

---

### CloudFront → ALB 통신 방식

```
사용자 ──HTTPS──→ CloudFront (엣지)
                      │
                   캐시 있으면 바로 응답
                   없으면 ↓
              ──HTTP──→ ALB (ap-northeast-2)
                           │
                      ──→ EC2
```

CloudFront가 HTTPS를 종료하고, ALB와는 HTTP로 통신해도 된다. (ALB에 ACM 없는 실습 환경에서 유리)

---

### Price Class — 엣지 로케이션 범위

| Price Class | 포함 리전 | 비용 |
|-------------|-----------|------|
| `PriceClass_100` | 미주, 유럽 | 가장 저렴 |
| `PriceClass_200` | 미주, 유럽, 아시아, 중동, 아프리카 | 중간 (한국 포함) |
| `PriceClass_All` | 전체 | 가장 비쌈 |

---

### ALB 직접 접근 차단 방법

CloudFront를 앞에 두는 이유 중 하나는 WAF, DDoS 방어를 CloudFront에서 처리하기 위해서다. 그런데 ALB DNS로 직접 접근이 가능하면 CloudFront를 우회할 수 있다.

```
올바른 경로: 인터넷 → CloudFront → ALB → EC2
우회 경로:   인터넷 → ALB (직접) → EC2  ← 차단 필요
```

**차단 방법: ALB Security Group에 CloudFront IP 범위만 허용**

CloudFront의 IP 목록을 ALB SG inbound에 적용한다. AWS가 CloudFront IP를 **Managed Prefix List**로 관리하므로 직접 IP를 관리하지 않아도 된다.

```hcl
# ALB SG inbound에 CloudFront Managed Prefix List 적용
resource "aws_security_group_rule" "alb_from_cloudfront" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  prefix_list_ids   = ["pl-xxxxxxxx"]  # com.amazonaws.global.cloudfront.origin-facing
  security_group_id = aws_security_group.alb.id
}
```

> Managed Prefix List ID는 리전마다 다르다. `data "aws_ec2_managed_prefix_list"` data source로 조회하거나 콘솔에서 확인.

**대안: Custom Header 방식**

CloudFront가 ALB로 요청 시 특정 헤더(`X-Origin-Secret: xxx`)를 추가하고, ALB WAF에서 이 헤더 없으면 차단. 더 유연하지만 구현이 복잡하다.

---

### `origin_protocol_policy` — CloudFront → origin 구간 프로토콜

`origin_protocol_policy`는 CloudFront가 origin(ALB)과 통신할 때 사용하는 프로토콜을 결정한다.

```
사용자 ──HTTPS──→ CloudFront ──[여기]──→ ALB
                              ↑
                   origin_protocol_policy
```

| 값 | 사용 상황 |
|----|---------|
| `http-only` | ALB에 ACM 없을 때 (HTTP:80으로만 통신) |
| `https-only` | ALB에도 ACM 인증서가 있을 때 (End-to-End 암호화) |
| `match-viewer` | 사용자 프로토콜을 그대로 따라감 (거의 미사용) |

**`match-viewer`를 잘 안 쓰는 이유**: `viewer_protocol_policy = "redirect-to-https"`로 사용자 구간을 HTTPS 강제하면 어차피 항상 HTTPS가 되므로 의미가 없어진다.

**이 프로젝트에서 변경 시점**: 도메인 확보 후 ALB에도 ACM 인증서를 붙이면 `http-only` → `https-only`로 변경. 실무에서는 CloudFront↔ALB 구간도 암호화하는 것이 권장 사항이다.

---

### 커스텀 도메인 연결 방법

도메인 확보 후 두 곳을 수정해야 한다.

**1. CloudFront — `aliases` + `viewer_certificate` 교체**

```hcl
resource "aws_cloudfront_distribution" "main" {
  aliases = ["example.com", "www.example.com"]  # 없으면 커스텀 도메인 요청을 거부 (403)

  viewer_certificate {
    # cloudfront_default_certificate = true  ← 이 줄 삭제
    acm_certificate_arn      = var.cf_certificate_arn  # us-east-1 ACM 필수
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
```

**2. Route53 — A 레코드 Alias로 CloudFront 연결**

```hcl
resource "aws_route53_record" "root" {
  zone_id = var.hosted_zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false  # CloudFront는 health check 미지원
  }
}
```

---

### 실무에서 자주 하는 실수

1. **API 서버에 캐시 적용** → TTL 설정하면 API 응답이 캐시되어 오래된 데이터 반환. API는 TTL=0으로 설정
2. **ALB 직접 접근 차단 안 함** → CloudFront 없이 ALB DNS로 직접 접근 가능해 WAF 우회됨. ALB SG에 CloudFront Managed Prefix List 적용 필수
3. **us-east-1 ACM 미사용** → CloudFront는 반드시 us-east-1 리전의 ACM 인증서만 허용
4. **aliases 미설정** → 커스텀 도메인 연결 후 `aliases`에 도메인 등록 안 하면 CloudFront가 요청을 거부(403)

---

## 2. Terraform 핵심 파라미터

### `aws_cloudfront_distribution`

**`origin` 블록:**

| 인수 | 필수 | 설명 |
|------|------|------|
| `domain_name` | ✅ | 오리진 도메인 (ALB DNS 이름) |
| `origin_id` | ✅ | 이 오리진의 식별자. `default_cache_behavior`의 `target_origin_id`와 일치해야 함 |
| `custom_origin_config` | ALB 시 ✅ | ALB는 S3가 아니므로 필수 |

**`custom_origin_config` 블록:**

| 인수 | 필수 | 설명 |
|------|------|------|
| `http_port` | ✅ | 오리진 HTTP 포트. 보통 80 |
| `https_port` | ✅ | 오리진 HTTPS 포트. 보통 443 |
| `origin_protocol_policy` | ✅ | `http-only` / `https-only` / `match-viewer` |
| `origin_ssl_protocols` | ✅ | HTTPS 사용 시 허용 TLS 버전. `["TLSv1.2"]` |

**`default_cache_behavior` 블록:**

| 인수 | 필수 | 설명 |
|------|------|------|
| `target_origin_id` | ✅ | origin의 `origin_id`와 일치 |
| `viewer_protocol_policy` | ✅ | `redirect-to-https` / `https-only` / `allow-all` |
| `allowed_methods` | ✅ | 허용할 HTTP 메서드 목록 |
| `cached_methods` | ✅ | 실제로 캐시할 메서드. 보통 `["GET", "HEAD"]` |
| `forwarded_values` | ✅ | 오리진에 전달할 헤더/쿠키/쿼리스트링 |
| `min_ttl` / `default_ttl` / `max_ttl` | 선택 | 캐시 유지 시간(초). 0이면 캐시 안 함 |

**최상위 인수:**

| 인수 | 필수 | 설명 |
|------|------|------|
| `enabled` | ✅ | `true` = 배포 활성화 |
| `price_class` | 선택 | `PriceClass_200` 권장 (한국 포함) |
| `http_version` | 선택 | `"http2and3"` 권장 |
| `is_ipv6_enabled` | 선택 | `true` 권장 |
| `restrictions` | ✅ | 지역 제한 블록. 없으면 에러 |
| `viewer_certificate` | ✅ | 도메인 없으면 `cloudfront_default_certificate = true` |

---

### `custom_error_response` 블록 — 에러 응답 처리

CloudFront가 오리진에서 에러를 받았을 때 처리 방식을 정의한다.

**에러가 발생하는 상황:**
```
502 Bad Gateway       — ALB가 EC2에 연결 실패
503 Service Unavail   — Target Group에 healthy 인스턴스 없음
504 Gateway Timeout   — EC2 응답 시간 초과
404 Not Found         — 존재하지 않는 경로
```

```hcl
custom_error_response {
  error_code            = 502   # 가로챌 HTTP 에러 코드
  response_code         = 200   # 사용자에게 돌려줄 상태 코드 (선택)
  response_page_path    = "/error.html"  # 보여줄 경로 (선택)
  error_caching_min_ttl = 0     # 에러 응답 캐시 시간. 기본 300초
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `error_code` | ✅ | 가로챌 HTTP 에러 코드 (400~599) |
| `response_code` | 선택 | 사용자에게 돌려줄 상태 코드. 미설정 시 원본 에러 코드 그대로 |
| `response_page_path` | 선택 | 보여줄 페이지 경로. `/`로 시작해야 함 |
| `error_caching_min_ttl` | 선택 | 에러 응답 캐시 시간(초). **기본 300초 → 서버 복구 후 5분간 에러 지속** |

> **`error_caching_min_ttl = 0` 필수**: 기본 300초 캐시로 인해 서버가 복구됐는데도 사용자에게 5분간 에러를 반환할 수 있다.

**패턴 1 — API 서버: 에러 그대로 전달 + 캐시만 끔**
```hcl
# 오리진 장애 에러는 캐시하지 않고 즉시 재시도
custom_error_response { error_code = 502; error_caching_min_ttl = 0 }
custom_error_response { error_code = 503; error_caching_min_ttl = 0 }
custom_error_response { error_code = 504; error_caching_min_ttl = 0 }
```

**패턴 2 — SPA(React/Vue): 404를 index.html로**
```hcl
# 클라이언트 사이드 라우팅 — 실제 파일 없어도 index.html 반환
custom_error_response {
  error_code            = 404
  response_code         = 200
  response_page_path    = "/index.html"
  error_caching_min_ttl = 0
}
```

---

## 3. 이 프로젝트에서의 위치

```
Phase 3 — Web Tier (envs/dev/web/)
  ├── ALB        ← 선행 (alb_dns_name 참조)
  ├── CloudFront ← 여기
  ├── WAF        ← 후행 (이 Distribution에 연결)
  └── Route53    ← 후행 (cloudfront_domain_name을 Alias로 가리킴)
```

**outputs.tf에 노출할 값:**
- `cloudfront_domain_name` — Route53 Alias 타겟
- `cloudfront_distribution_id` — WAF 연결, Cache Invalidation에 사용

---

## 4. 직접 해볼 것

- `modules/web/cloudfront.tf` 생성
- `viewer_certificate { cloudfront_default_certificate = true }` 로 도메인 없이 시작
- apply 후 `xxx.cloudfront.net` 으로 접근 확인

**공식 문서**: [CloudFront Distribution](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-working-with.html)
**검색 키워드**: `aws_cloudfront_distribution terraform`, `cloudfront alb origin`, `cloudfront cache behavior`
