# Terraform 인프라 테스트 전략

> 마지막 업데이트: 2026-03-07

---

## 왜 인프라 테스트가 어려운가

코드는 알파 서버를 만들어서 테스트할 수 있지만, 인프라는 그렇지 않다.

- dev 환경을 따로 구축하기 어려운 상황이 많다
- dev와 prod 구조가 완전히 같지 않을 수 있다 (비용, 규모, HA 구성 차이)
- 실제 AWS 리소스를 만들어야 하므로 테스트 자체에 비용이 발생한다
- 잘못된 설정으로 apply하면 장애로 이어질 수 있다

---

## 인프라 테스트 방법 4가지

### 1. `terraform plan` 리뷰 (가장 기본)

실제 apply 전에 plan 결과를 PR에 자동으로 올려 사람이 검토한다.

```
GitHub Actions → terraform plan → PR 코멘트에 결과 출력 → 사람이 검토 후 merge → apply
```

- 비용: 없음
- 신뢰도: 낮음 (사람이 놓칠 수 있음)
- 실무 사용: 항상 (기본 중의 기본)

---

### 2. `tfsec` / `checkov` — 정적 분석

실제 AWS 리소스를 만들지 않고 `.tf` 코드만 분석해서 보안 문제를 찾는다.

```bash
# 설치
brew install tfsec

# 전체 실행
tfsec .

# 심각도 필터 (HIGH 이상만)
tfsec . --minimum-severity HIGH

# 특정 레이어만
tfsec envs/dev/network/
```

출력 예시:
```
CRITICAL  S3 버킷에 퍼블릭 액세스 차단이 없음
HIGH      Security Group에 0.0.0.0/0 inbound 허용
MEDIUM    RDS 암호화가 비활성화됨
```

GitHub Actions에 통합:
```yaml
- name: tfsec
  uses: aquasecurity/tfsec-action@v1.0.0
```

#### tfsec 이슈 분류 기준 (실제 프로젝트 경험)

tfsec 결과를 보면 모두 고쳐야 할 것처럼 보이지만, 실제로는 3가지로 분류해야 한다:

**1. 실제 수정 필요**
```
ALB drop_invalid_header_fields 미설정  → HTTP Smuggling 취약, 한 줄 추가로 해결
CloudFront viewer_protocol_policy HTTP 허용 → 평문 통신 가능, redirect-to-https로 변경
S3 버킷 SSE 암호화 없음               → AES256 또는 aws:kms로 암호화 추가
SNS/CloudTrail KMS 암호화 없음        → alias/aws/sns 등 AWS 관리 키 추가
```

**2. 의도적 설계 — tfsec ignore 처리**
```
HTTP listener 사용  → 리다이렉트 전용 (80→443), HTTP가 맞음
ALB internal=false  → 인터넷 facing ALB는 당연히 public
```

```hcl
# 해당 라인 위에 주석으로 ignore 추가
# tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" { ... }

# tfsec:ignore:aws-elb-alb-not-public
internal = false
```

**3. 비용/환경 고려 — dev 한정 ignore**
```
RDS CMK 미사용    → storage_encrypted=true (AWS 관리 키)로 충분, CMK는 compliance 요구 시만
CloudTrail KMS    → KMS 키 생성 비용 발생, dev 환경에서는 생략 가능
```

> **원칙**: tfsec는 보수적으로 판단하므로 결과를 그대로 따르지 않고, 설계 의도와 비용을 고려해 분류해야 한다.

| | tfsec | checkov |
|---|---|---|
| 특화 | Terraform 전용 | Terraform, K8s, Dockerfile 등 다양 |
| 속도 | 빠름 | 느림 |
| 규칙 수 | 적음 | 많음 |

- 비용: 없음
- 신뢰도: 중간 (런타임 값은 분석 불가)
- 실무 사용: 자주

---

### 3. dev 환경 apply — 실제 검증

dev 환경에 실제로 apply해서 검증한 뒤 prod에 적용한다.

- 비용: 있음 (리소스 생성 비용)
- 신뢰도: 높음
- 실무 사용: 자주

**dev/prod 구조 차이 문제 해결:**

"완전히 같은 구조, 다른 크기"로 설계하면 dev 검증이 prod에도 유효하다.

```hcl
# dev
nat_gateway_count = 1       # 비용 절감
instance_type     = "t3.micro"

# prod
nat_gateway_count = 2       # AZ별 HA
instance_type     = "t3.medium"
```

구조(모듈, 리소스 관계)는 같고 변수(크기, 수량)만 다르게 → dev와 prod가 같은 코드를 공유하면서 다른 설정으로 실행된다.

---

### 4. `Terratest` — 코드로 작성하는 인프라 테스트

Go 언어로 테스트를 작성한다. 실제 AWS에 리소스를 생성하고, 검증하고, 자동으로 삭제한다.

```
실제 AWS에 리소스 생성 → 검증 (VPC CIDR 맞는지, SG rule 맞는지 등) → 자동 destroy
```

- 비용: 높음 (테스트마다 실제 리소스 생성/삭제)
- 신뢰도: 매우 높음
- 실무 사용: 드물게 (대기업 또는 핵심 공유 모듈에만)

---

## 실무 조합

| 방법 | 비용 | 신뢰도 | 실무 사용 |
|------|------|--------|---------|
| plan 리뷰 | 없음 | 낮음 | 항상 |
| tfsec/checkov | 없음 | 중간 | 자주 |
| dev 환경 apply | 있음 | 높음 | 자주 |
| Terratest | 높음 | 매우 높음 | 드물게 |

대부분의 팀: **plan 리뷰 + tfsec + dev apply** 조합으로 운영

---

## tfsec 동작 원리 — AST 기반 정적 분석

tfsec은 실제 AWS API를 호출하지 않고, `.tf` 파일을 파싱해서 코드 구조만으로 문제를 찾는다.

### 동작 단계

**1단계 — 파싱**: `.tf` 파일을 읽어 AST(Abstract Syntax Tree)로 변환

```
resource "aws_s3_bucket" "example" { ... }
→ Resource { type: "aws_s3_bucket", attributes: { ... } }
```

**2단계 — 규칙 매칭**: 미리 정의된 규칙과 AST를 비교

```
규칙: aws_s3_bucket에 server_side_encryption_configuration이 없으면 → CRITICAL
→ 트리에서 해당 속성 탐색 → 없음 → 경고 출력
```

**3단계 — 결과 출력**: 위반 항목, 심각도, 파일 위치 출력

컴파일러가 코드를 실행하지 않고도 타입 오류를 잡는 것과 같은 원리다.

### 한계 (정적 분석의 근본적 제약)

런타임에 결정되는 값은 분석할 수 없다.

```hcl
# 잡을 수 있음 — 값이 코드에 있음
cidr_blocks = ["0.0.0.0/0"]

# 못 잡을 수도 있음 — 값이 변수에 있음
cidr_blocks = var.allowed_cidrs
```

이 때문에 정적 분석만으로는 부족하고, plan 리뷰나 dev apply와 병행해야 한다.

---

## 이 프로젝트에서의 적용

**Phase 7 — IaC Best Practices**에서 CI/CD 파이프라인 구성 시 적용한다.

```yaml
# GitHub Actions 예시
jobs:
  validate:
    steps:
      - run: terraform fmt -check
      - run: terraform validate
      - uses: aquasecurity/tfsec-action@v1.0.0
  plan:
    steps:
      - run: terraform plan
        # PR 코멘트에 plan 결과 자동 출력
  apply:
    if: github.ref == 'refs/heads/main'
    steps:
      - run: terraform apply -auto-approve
```
