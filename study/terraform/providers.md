# Terraform Provider

> 마지막 업데이트: 2026-03-08

---

## 1. Provider란

Terraform이 AWS API를 호출하기 위한 **드라이버**다. 어느 리전에, 어느 계정으로 리소스를 만들지를 결정한다.

```hcl
provider "aws" {
  region = "ap-northeast-2"  # 이 provider로 만든 리소스는 서울에 생성
}
```

Provider가 없으면 Terraform은 AWS에 아무것도 할 수 없다. `terraform init`이 provider 플러그인을 다운로드하는 단계다.

---

## 2. 왜 variable로 전달할 수 없는가

Terraform 실행은 두 단계로 나뉜다:

```
1단계 — 초기화 (terraform init)
  provider 플러그인 다운로드
  어느 리전/계정 쓸지 결정 (provider 설정 확정)
  ↓
2단계 — 실행 (terraform plan/apply)
  variable 값 읽기
  리소스 생성/수정/삭제
```

`variable`은 2단계에서 읽힌다. provider는 1단계에서 이미 확정되어야 하므로 variable로 provider를 동적으로 설정할 수 없다.

```hcl
# ❌ 불가 — plan 시점에 이미 provider가 확정되어야 함
provider "aws" {
  region = var.region
}

# ✅ 상수값 사용
provider "aws" {
  region = "ap-northeast-2"
}
```

---

## 3. Provider Alias — 여러 리전 동시 사용

같은 코드에서 여러 리전을 동시에 사용할 때 `alias`로 구분한다.

```hcl
# 기본 provider (alias 없음) — 반드시 하나 있어야 함
provider "aws" {
  region = "ap-northeast-2"
}

# alias provider — 추가로 선언
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

```hcl
# 기본 provider 사용 (서울에 생성)
resource "aws_lb" "alb" { ... }

# alias provider 사용 (버지니아에 생성)
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  ...
}
```

> **기본 provider는 반드시 하나 있어야 한다.** alias만 있고 기본 provider가 없으면 에러 발생. 기본 provider 블록에 내용이 없어도 되지만 (환경변수에서 리전을 읽음), 명시적으로 리전을 적는 것이 권장된다.

---

## 4. Module에 Provider 전달

Child module이 provider alias를 사용하면, 호출자가 `providers` 블록으로 명시적으로 전달해야 한다.

```hcl
# envs/dev/web/main.tf
module "web" {
  source = "../../../modules/web"

  providers = {
    aws           = aws            # 기본 provider (ap-northeast-2)
    aws.us_east_1 = aws.us_east_1  # alias provider (us-east-1)
  }
}
```

**중요 제약사항**: Module에 provider를 선택적으로 전달하는 기능은 없다. Module 내부에서 `provider = aws.us_east_1`을 사용하는 리소스가 `count = 0`이어도, 호출자는 반드시 해당 provider를 `providers` 블록에 전달해야 한다.

→ 해결 방법: 특정 리전에서만 동작하는 리소스(WAF, ACM 등)는 별도 모듈로 분리하거나, 항상 provider를 전달하는 구조로 설계한다.

---

## 5. 이 프로젝트에서의 패턴

```
modules/web/
  alb.tf        → provider: aws (ap-northeast-2) — 기본 provider 사용
  cloudfront.tf → provider: aws (ap-northeast-2)
  waf.tf        → provider: aws.us_east_1        — CloudFront WAF는 us-east-1 필수

envs/dev/web/main.tf
  provider "aws" { region = "ap-northeast-2" }   # 기본
  provider "aws" { alias = "us_east_1", region = "us-east-1" }  # WAF/ACM용

  module "web" {
    providers = {
      aws           = aws
      aws.us_east_1 = aws.us_east_1
    }
  }
```

us-east-1이 필요한 AWS 리소스: CloudFront용 **ACM**, **WAF** (두 서비스 모두 CloudFront에 붙이는 것은 us-east-1 고정)

---

## 참고

- Provider 공식 문서: https://developer.hashicorp.com/terraform/language/providers/configuration
- 검색 키워드: `terraform provider alias`, `terraform module providers argument`
