# Terraform 실무 고려사항
> 마지막 업데이트: 2026-04-04

실제로 팀이 Terraform을 운영할 때 부딪히는 문제들이다.
코드는 잘 짰는데 운영에서 사고가 나는 이유가 대부분 여기에 있다.

---

## 1. 실수로 prod destroy — 가장 위험한 상황

### 문제
```bash
# 실수로 prod 환경에서 실행
terraform destroy
# 또는 plan에서 예상치 못한 destroy가 포함된 채로 apply
```

### 대책

**1) prevent_destroy 사용**
```hcl
resource "aws_rds_cluster" "main" {
  lifecycle {
    prevent_destroy = true
  }
}
```
삭제 시도 시 에러 발생. 단, `terraform destroy`는 막지 못함 (lifecycle 자체를 지워야 함).

**2) workspace 또는 별도 디렉토리로 환경 격리**
```bash
# workspace 방식
terraform workspace select prod
# → 실수로 dev 코드를 prod에 적용하는 사고 방지

# 디렉토리 방식
envs/dev/
envs/prod/    ← 별도 state, 별도 backend key
```

**3) CI/CD에서만 apply 허용**
- 개발자 로컬에서 `terraform apply` 금지
- PR 머지 시 CI/CD 파이프라인에서만 apply
- 사람 실수 원천 차단

---

## 2. State에 민감 정보가 저장되는 문제

Terraform state는 평문 JSON이다. 리소스를 생성하면 그 속성이 전부 state에 기록된다.

```json
// terraform.tfstate 예시
{
  "resources": [{
    "type": "aws_db_instance",
    "instances": [{
      "attributes": {
        "password": "my-secret-password-123",  // 평문으로 저장됨!
        "username": "admin"
      }
    }]
  }]
}
```

### 대책
- **Remote Backend 필수** — S3 + 서버 사이드 암호화(SSE) 활성화
- **S3 버킷 정책** — state 파일 접근 권한 최소화
- **민감값은 Secrets Manager에서 참조** — state에 실제 값 대신 ARN만 저장되도록

```hcl
# 나쁜 예: 값을 직접 넣으면 state에 평문으로 저장됨
resource "aws_db_instance" "main" {
  password = "hardcoded-password"
}

# 좋은 예: Secrets Manager에서 가져오기
data "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
}
resource "aws_db_instance" "main" {
  password = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]
}
```

---

## 3. provider / module 버전 고정

버전을 고정하지 않으면 팀원마다 다른 버전을 쓰게 되고, 예상치 못한 동작이 생긴다.

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # 5.x 범위 내에서만 업그레이드 허용
    }
  }
}
```

```hcl
# module 버전도 고정
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"   # 정확한 버전 고정
}
```

**`.terraform.lock.hcl` 파일을 반드시 Git에 커밋할 것.**
이 파일이 있어야 팀 전체가 동일한 provider 버전을 사용한다.

---

## 4. 대규모 State 분리 전략

하나의 state에 모든 리소스를 넣으면:
- `terraform plan`이 느려진다 (AWS API 수백 번 호출)
- 한 리소스 변경 시 전체가 잠긴다 (state lock)
- 실수 한 번에 전체 인프라가 위험해진다

### 분리 기준

```
# 변경 주기별 분리 (권장)
state/
  network/     ← VPC, Subnet, IGW (거의 안 바뀜)
  security/    ← SG, IAM, NACL (가끔 바뀜)
  compute/     ← EC2, ASG (자주 바뀜)
  database/    ← RDS, ElastiCache (거의 안 바뀜)
  monitoring/  ← CloudWatch, SNS
```

각 state는 `terraform_remote_state`로 연결.

---

## 5. CI/CD 통합 패턴

### PR 단계에서 plan 결과 노출

```yaml
# GitHub Actions 예시 구조
on: pull_request

jobs:
  terraform-plan:
    steps:
      - run: terraform init
      - run: terraform plan -out=tfplan
      - run: terraform show -json tfplan | jq  # PR 코멘트로 게시
```

PR에서 `plan` 결과를 리뷰하면 실수로 destroy가 포함된 코드가 머지되는 것을 방지할 수 있다.

### apply는 main 머지 후만

```
PR 열림  →  terraform plan  →  결과를 PR 코멘트에 게시
main 머지  →  terraform apply  →  결과를 Slack/알림으로 전송
```

### OIDC 인증 (Access Key 없이 AWS 접근)

```hcl
# GitHub Actions용 OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  # ...
}
```
CI 서버에 AWS Access Key를 저장하지 않아도 됨. 보안 사고 예방에 중요.

---

## 6. 리소스 드리프트 (Drift) 관리

팀원이 콘솔에서 직접 변경하면 state와 실제 인프라가 어긋난다.

### 감지
```bash
# 실제 인프라 상태로 state 갱신 후 diff 확인
terraform plan -refresh-only

# 정기적으로 실행해서 drift 조기 발견
```

### 대책
- **콘솔 직접 변경 금지 정책** — IAM으로 콘솔 write 권한 제한
- **정기 plan 스케줄** — 매일 `terraform plan`을 실행하고 변경 감지 시 알림
- **태그로 Terraform 관리 여부 명시**
```hcl
default_tags {
  tags = {
    ManagedBy = "Terraform"
  }
}
```

---

## 7. 비용 관리

Terraform으로 리소스를 쉽게 만들 수 있는 만큼 실수로 비싼 리소스가 남는 경우가 많다.

### 실수 유형
```hcl
# NAT Gateway: 존재만 해도 월 ~$32/개 (데이터 전송 비용 별도)
# RDS Multi-AZ: 단순히 multi_az = true 추가하면 비용 2배
# NAT 인스턴스 vs Gateway 비용 차이 인지 필요
```

### 대책
- **infracost** — `terraform plan` 결과를 비용 예측으로 변환
```bash
infracost breakdown --path .
# Before: $152/month
# After:  $287/month (+$135)
```
- PR 단계에서 비용 증가분을 자동으로 코멘트로 게시

---

## 8. 타임아웃 설정

RDS, ElastiCache 등 생성/삭제에 오래 걸리는 리소스는 기본 타임아웃이 부족할 수 있다.

```hcl
resource "aws_rds_cluster" "main" {
  # ...

  timeouts {
    create = "60m"   # 기본값: 120m (충분하지만 명시적으로)
    update = "60m"
    delete = "60m"
  }
}
```

CI/CD에서 apply가 타임아웃으로 실패하면 state는 업데이트됐는데 파이프라인은 실패로 표시되는 혼란이 생긴다. 명시적으로 설정해두는 게 낫다.

---

## 9. 팀 협업 규칙

### State Lock 충돌 방지
```bash
# 두 사람이 동시에 apply하면 한 명은 lock 에러
# Error: Error acquiring the state lock

# 해결: 한 번에 한 명만 apply (CI/CD로 직렬화)
# 또는 workspace로 환경 분리
```

### 코드 리뷰 체크리스트
plan 결과에서 반드시 확인:
- `destroy`가 있는가? → 의도한 것인가?
- `forces replacement`가 있는가? → 서비스 중단 발생
- 비용 변화가 큰가?

### 공통 변수 관리
```hcl
# 팀 전체가 쓰는 값은 중앙에서 관리
# envs/common.tfvars 또는 Parameter Store 참조
```

---

## 10. 흔히 놓치는 것들

### AMI ID 하드코딩
```hcl
# 나쁨: 리전마다 다르고 deprecated됨
ami = "ami-0c9c942bd7bf113a2"

# 좋음: 항상 최신 AMI를 동적으로 참조
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### depends_on 과용
```hcl
# IAM role 생성 후 EC2가 그 role을 참조하는 경우
# Terraform이 참조 관계로 자동 추론함 → depends_on 불필요
# depends_on은 암묵적 의존성이 있을 때만 (주로 provisioner, null_resource)
```

### ignore_changes 남용
```hcl
lifecycle {
  ignore_changes = [tags, ami]  # 이게 쌓이면 실제 변경을 감지 못함
}
# 꼭 필요한 경우에만, 이유를 주석으로 명시
```

### for_each에 map 대신 set 사용
```hcl
# set은 순서가 없어서 변경 시 전체 재생성 위험
for_each = toset(var.subnet_cidrs)   # 위험

# map 사용 권장 (key가 고정되어 안전)
for_each = {
  "ap-northeast-2a" = "10.0.1.0/24"
  "ap-northeast-2c" = "10.0.2.0/24"
}
```

---

## 관련 파일
- `study/terraform/state-management.md` — State 조작 명령어
- `study/terraform/backend.md` — Remote Backend 설정
- `study/terraform/anti-patterns.md` — 안티패턴 목록
- `study/terraform/lifecycle-and-import.md` — lifecycle, prevent_destroy