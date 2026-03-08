# WAF (Web Application Firewall)

> 마지막 업데이트: 2026-03-08
> Phase: Phase 3 — Web Tier

---

## 1. 개념 설명

### WAF란

**Web Application Firewall**. HTTP/HTTPS 요청을 검사해서 악성 트래픽을 차단한다. CloudFront, ALB, API Gateway 앞에 붙는 L7 방어막이다.

```
인터넷 → CloudFront → WAF 검사 → ALB → EC2
                        ↑
              여기서 악성 요청 차단
```

방화벽(SG, NACL)이 IP/포트 기반으로 차단한다면, WAF는 **HTTP 요청 내용** 기반으로 차단한다.

---

### WAF가 막는 것

| 공격 유형 | 예시 |
|---------|------|
| SQL Injection | `SELECT * FROM users WHERE id=1 OR 1=1` |
| XSS | `<script>document.cookie</script>` |
| 특정 IP/국가 차단 | 특정 IP 대역 블랙리스트 |
| Rate Limiting | 1분에 1000회 이상 요청하는 IP 차단 |
| Known Bad Inputs | 알려진 악성 페이로드 패턴 |

---

### Rules와 Rule Groups

WAF는 **Rule 목록**으로 동작한다. 요청이 Rule에 매칭되면 `Allow` / `Block` / `Count` 중 하나를 실행한다.

```
요청 → Rule 1 검사 → Rule 2 검사 → Rule 3 검사 → 통과 → origin
              ↓
           Block → 403 반환
```

**AWS Managed Rule Groups** — AWS가 미리 만들어둔 Rule 묶음. 직접 규칙을 짜지 않아도 된다.

| Managed Rule Group | 차단 대상 |
|------------------|---------|
| `AWSManagedRulesCommonRuleSet` | OWASP Top 10 (SQL Injection, XSS 등) |
| `AWSManagedRulesKnownBadInputsRuleSet` | 알려진 악성 입력값 |
| `AWSManagedRulesAmazonIpReputationList` | AWS가 악성으로 분류한 IP |
| `AWSManagedRulesBotControlRuleSet` | 봇 트래픽 |

---

### WAF 연결 대상 (scope)

WAF는 어디에 붙이느냐에 따라 `scope`가 달라진다:

| 연결 대상 | scope | 생성 리전 |
|---------|-------|---------|
| CloudFront | `CLOUDFRONT` | **반드시 us-east-1** |
| ALB | `REGIONAL` | ALB와 같은 리전 |
| API Gateway | `REGIONAL` | API GW와 같은 리전 |

CloudFront용 WAF를 ap-northeast-2에 만들면 CloudFront에 연결 불가. ACM과 같은 이유다.

> **오개념 주의**: `scope`는 WAF의 **생성 위치**를 결정하는 것이지, 어느 지역에서 오는 트래픽을 막는다는 의미가 아니다. 특정 국가/IP 차단은 WAF Rule 안에 `geo_match_statement`로 별도 설정한다.

---

### CloudFront vs ALB 연결 방법 차이

WAF 리소스 자체에는 연결 대상 설정이 없다. **연결 대상 리소스에서 WAF를 참조**하는 방식이다.

| 연결 대상 | 방법 |
|---------|------|
| CloudFront | distribution의 `web_acl_id` 속성에 직접 지정 |
| ALB | 별도 리소스 `aws_wafv2_web_acl_association` 필요 |

> **`web_acl_id` 주의**: 이름이 `_id`지만 실제로는 **ARN**을 넣어야 한다. ID와 ARN을 혼동하면 에러 발생.

---

### Count 모드 — 차단 전 모니터링

Rule을 `Block`이 아닌 `Count`로 설정하면 차단하지 않고 카운트만 한다. 새 Rule 적용 전 **오탐(False Positive) 검증**에 쓴다.

```
새 Rule 추가 시:
1. Count 모드로 배포 → CloudWatch에서 얼마나 걸리는지 확인
2. 정상 트래픽에 영향 없으면 → Block 모드로 전환
```

---

### 실무에서 자주 하는 실수

1. **scope 불일치** — CloudFront용 WAF를 ap-northeast-2에 만들면 CloudFront에 연결 불가
2. **Managed Rule Group 과잉 적용** — 모든 Rule Group 다 켜면 정상 요청도 차단될 수 있음. `AWSManagedRulesCommonRuleSet`부터 시작
3. **Count 모드 없이 바로 Block** — 오탐으로 정상 사용자 차단 위험
4. **WAF 비용** — Managed Rule Group당 월 $1 + 요청 수 과금. Rule Group 수를 최소화

---

## 2. Terraform 핵심 파라미터

### `aws_wafv2_web_acl`

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | Web ACL 이름 |
| `scope` | ✅ | `CLOUDFRONT` 또는 `REGIONAL` |
| `default_action` | ✅ | Rule에 매칭 안 된 요청의 기본 처리. `allow {}` 또는 `block {}` |
| `rule` | 선택 | 개별 Rule 블록. 여러 개 선언 가능 |
| `visibility_config` | ✅ | CloudWatch 메트릭 설정 |

**`rule` 블록:**

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | Rule 이름 |
| `priority` | ✅ | Rule 평가 순서. 낮을수록 먼저 평가 |
| `action` | 커스텀 Rule 시 ✅ | `allow {}` / `block {}` / `count {}` |
| `override_action` | Managed Rule Group 시 ✅ | `none {}` (Rule Group 내부 action 그대로) 또는 `count {}` (전체 count로 override) |
| `statement` | ✅ | 매칭 조건. `managed_rule_group_statement` 등 |
| `visibility_config` | ✅ | 이 Rule의 CloudWatch 메트릭 설정 |

> **`action` vs `override_action`**: Managed Rule Group은 내부적으로 이미 action(block/allow 등)이 정의되어 있다. 그래서 `action` 대신 `override_action`을 써야 한다. `none {}`은 Rule Group 내부 action을 그대로 따르겠다는 의미. 커스텀 Rule(직접 만든 조건)은 `action`을 써야 한다.

**Managed Rule Group 사용:**

```hcl
statement {
  managed_rule_group_statement {
    vendor_name = "AWS"
    name        = "AWSManagedRulesCommonRuleSet"
  }
}
```

**CloudFront에 WAF 연결:**

```hcl
resource "aws_cloudfront_distribution" "main" {
  web_acl_id = aws_wafv2_web_acl.main.arn
  ...
}
```

**provider alias 필수 (CloudFront용):**

```hcl
# modules/web/ 또는 envs/dev/web/에 us-east-1 provider 추가 필요
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  scope    = "CLOUDFRONT"
  ...
}
```

---

## 3. 이 프로젝트에서의 위치

```
Phase 3 — Web Tier (envs/dev/web/)
  ├── ALB        ✅ 완료
  ├── CloudFront ✅ 완료
  ├── WAF        ← 여기 (modules/web/waf.tf)
  └── Route53    ← 도메인 확보 후
```

**선행 리소스**: `aws_cloudfront_distribution` (WAF ARN을 여기에 연결)

**outputs.tf에 노출할 값:**
- `waf_arn` — CloudFront `web_acl_id`에 연결

---

## 4. 직접 해볼 것

- `modules/web/waf.tf` 생성
- `AWSManagedRulesCommonRuleSet` Rule Group 하나만 붙여서 시작
- `default_action = allow` (명시적으로 허용 목록만 차단하는 패턴)
- CloudFront `web_acl_id`에 WAF ARN 연결

**공식 문서**: [AWS WAFv2](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html)
**검색 키워드**: `aws_wafv2_web_acl terraform`, `WAF managed rule group cloudfront`, `WAF scope CLOUDFRONT`
