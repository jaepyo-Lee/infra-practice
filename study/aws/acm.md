# ACM (AWS Certificate Manager)

> 마지막 업데이트: 2026-03-07 (HTTPS 전체 흐름, CNAME 소유권 원리, 오개념 교정 추가)

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

---

## 5. HTTPS가 되기까지 전체 흐름

ACM 하나만으로 HTTPS가 되는 게 아니다. 여러 서비스가 순서대로 연결된다.

### 등장인물

| 역할 | 서비스 |
|------|------|
| 도메인 이름 | Route53 또는 외부 도메인 업체 |
| DNS 서버 | Route53 Hosted Zone |
| SSL 인증서 | ACM |
| 트래픽 받는 곳 | ALB 또는 CloudFront |

### 6단계 흐름

```
1. [도메인 구입] example.com 구입
        ↓
2. [Route53 Hosted Zone 생성]
   example.com의 DNS 서버 역할을 Route53이 담당
   → NS 레코드 4개 발급 → 외부 도메인 업체에 등록 (위임)
        ↓
3. [ACM 인증서 요청]
   "example.com HTTPS 인증서 주세요"
   → ACM: "도메인 주인임을 증명해봐" → CNAME 레코드 발급
        ↓
4. [DNS 검증 — 소유권 증명]
   ACM이 발급한 CNAME을 Route53에 등록
   → ACM이 레코드 확인 → 인증서 발급 완료 (ISSUED)
        ↓
5. [ALB/CloudFront에 인증서 연결]
   발급된 인증서를 ALB 리스너 또는 CloudFront에 붙임
   → HTTPS 처리 가능해짐
        ↓
6. [Route53 A 레코드 등록]
   example.com → ALB DNS 주소로 연결
   → 사용자가 https://example.com 접속 가능
```

---

## 6. CNAME이 소유권 증명이 되는 이유

### 핵심 원리

**DNS 레코드는 도메인 주인만 수정할 수 있다.**

```
ACM: "내가 시키는 CNAME 레코드를 DNS에 등록해봐"
        ↓
사용자: Route53에 CNAME 등록
        ↓
ACM: "저 레코드가 실제로 있네 → 이 사람이 도메인 주인 맞다"
        ↓
인증서 발급
```

google.com CNAME을 수정할 수 있는 사람은 google.com 주인뿐이므로, CNAME 등록 자체가 소유권 증명이 된다.

### 비유

```
"이 집이 당신 집이야?" → "그럼 우편함에 이 편지 꽂아봐"
                                  ↓
편지를 꽂을 수 있음 = 집 주인이 맞음
```

CNAME 레코드 등록 = 우편함에 편지 꽂기

### 갱신 때도 같은 CNAME 재사용

검증 완료 후 CNAME 레코드를 **절대 삭제하면 안 된다.** ACM이 만료 60일 전 자동 갱신할 때 같은 CNAME으로 재검증하기 때문이다.

---

## 7. 오개념 교정

### "ACM 리소스만 만들면 자동으로 인증서가 발급되고 갱신된다"

❌ **틀렸다.**

```
aws_acm_certificate 생성
    ↓
"검증 대기" 상태 (PENDING_VALIDATION)  ← 여기서 멈춤
    ↓
DNS 검증 완료 필요  ← 이게 없으면 영원히 PENDING
    ↓
인증서 발급 완료 (ISSUED)
    ↓
이후 갱신은 자동
```

최초 발급 시 반드시 DNS 검증(CNAME 등록)이 필요하다. Terraform으로는 아래 세 리소스가 세트다:

```
aws_acm_certificate              ← 인증서 요청
aws_route53_record               ← CNAME 자동 등록
aws_acm_certificate_validation   ← 검증 완료 대기
```

`aws_acm_certificate_validation`이 없으면 검증되기 전에 다음 단계(ALB 연결)를 진행하려다 에러가 난다.

### "Route53이 없어도 ACM을 쓸 수 있다"

✅ **맞다.** 단, Route53 없이 쓰면 CNAME을 수동으로 외부 DNS에 등록해야 한다. Terraform 자동화가 불가능해진다. 실무에서 Route53과 ACM을 함께 쓰는 이유가 이것이다.