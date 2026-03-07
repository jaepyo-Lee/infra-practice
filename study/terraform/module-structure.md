# Terraform 모듈 구조 컨벤션

> **이 파일의 범위**: 파일/폴더 구조 컨벤션, provider 위치 규칙, 모듈별 outputs 목록
> **개념 및 데이터 흐름**: [core-blocks.md](./core-blocks.md) 참고

마지막 업데이트: 2026-03-07

---

## 1. 모듈 파일 분리 규칙

Terraform 모듈은 단일 `main.tf`에 모든 것을 담지 않고, **역할별로 파일을 분리**하는 것이 표준 컨벤션이다.

| 파일 | 담아야 할 것 |
|------|-------------|
| `main.tf` | 리소스 정의 (`resource`, `data` 블록) |
| `variables.tf` | 변수 선언 (`variable` 블록) |
| `outputs.tf` | 출력값 선언 (`output` 블록) |

### 왜 분리하는가?
- 협업 시 충돌 최소화: 각 파일의 책임이 명확해 PR 리뷰가 쉬움
- 탐색 용이성: `variables.tf`만 열면 이 모듈이 무엇을 받는지 바로 파악 가능
- Terraform 공식 스타일 가이드([hashicorp/terraform](https://developer.hashicorp.com/terraform/language/style))도 이 구조를 권장

### 안티패턴
```hcl
# ❌ iam.tf 안에 variable 선언 섞기
resource "aws_vpc" "main" { ... }

variable "cidr" {       # ← main.tf에 넣으면 안 됨
  type = string
}
```

---

## 2. `terraform {}` / `provider {}` 블록은 루트 모듈에만

### 핵심 원칙
**Child module(재사용 모듈)에는 `terraform {}`, `provider {}` 블록을 넣지 않는다.**

```
modules/vpc/main.tf     ← ❌ terraform {}, provider {} 넣으면 안 됨
envs/dev/main.tf        ← ✅ terraform {}, provider {} 는 여기에만
```

### 왜인가?
- Terraform은 **Provider Inheritance** 방식으로 동작한다.
- 루트 모듈이 provider를 선언하면, 그 안에서 호출하는 모든 child module은 자동으로 해당 provider를 상속받는다.
- child module에 provider를 직접 선언하면:
  - 모듈이 특정 리전/계정에 종속되어 재사용 불가
  - 루트 모듈의 provider 설정과 충돌 발생 가능
  - `terraform init` 시 provider 중복 문제 발생

### 올바른 구조
```
envs/
  dev/
    main.tf         ← terraform {}, provider "aws" {} 여기에만
    ↓ module "vpc" { source = "../../modules/vpc" }

modules/
  vpc/
    main.tf         ← resource "aws_vpc" "main" {} 만 있어야 함
    variables.tf
    outputs.tf
```

### provider를 모듈에 전달해야 할 경우
특수한 경우(예: 다른 리전 리소스) `providers` argument로 명시적 전달:
```hcl
module "us_east" {
  source    = "../../modules/vpc"
  providers = {
    aws = aws.us-east-1
  }
}
```

### provider alias 규칙 — 흔한 실수

**alias 이름에 하이픈(`-`) 불가, 언더스코어(`_`)만 허용**

```hcl
# ❌ 하이픈 사용 — 참조 시 aws.ap-northeast-2 불가
provider "aws" {
  alias  = "ap-northeast-2"
  region = "ap-northeast-2"
}

# ✅ 언더스코어 사용
provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"
}

# 참조 시
provider = aws.ap_northeast_2  # ✅
```

**alias provider만 선언하면 기본 provider가 사라진다**

```hcl
# ❌ 기본 provider 없음 — SG, IAM 등 다른 리소스가 어느 provider를 쓸지 모름
provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"
}

# ✅ alias와 별개로 기본 provider(alias 없음)를 반드시 선언
provider "aws" {
  region = "ap-northeast-2"  # 기본 provider
}

provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"  # alias provider
}
```

**module의 `providers` 블록에도 기본 `aws` 전달 필수**

```hcl
module "security" {
  source = "../../../modules/security"
  providers = {
    aws                = aws               # 기본 — 없으면 SG/IAM 등이 provider 못 찾음
    aws.us_east_1      = aws.us_east_1
    aws.ap_northeast_2 = aws.ap_northeast_2
  }
}
```

**child module에서 alias를 받으려면 `configuration_aliases` 선언 필요**

```hcl
# modules/security/versions.tf
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1, aws.ap_northeast_2]
    }
  }
}
```

---

## 3. `outputs.tf` — 모듈별 노출해야 할 값들

다른 모듈이 참조할 값들을 `outputs.tf`에 선언해야 한다.
**원칙: 내 모듈을 쓰는 다른 모듈이 필요로 하는 값은 전부 노출한다.**

> output 개념 및 동작 원리 → [core-blocks.md](./core-blocks.md) 참고

### 모듈별 최소 output 목록

| 모듈 | 노출해야 할 output | 참조하는 모듈 |
|------|-------------------|--------------|
| `vpc` | `vpc_id` | security_groups, alb, rds, elasticache |
| `vpc` | `public_subnet_ids` | alb, nat_gateway |
| `vpc` | `private_app_subnet_ids` | asg |
| `vpc` | `private_db_subnet_ids` | rds, elasticache |
| `security_groups` | `alb_sg_id` | alb |
| `security_groups` | `app_sg_id` | asg |
| `security_groups` | `db_sg_id` | rds, elasticache |
| `alb` | `alb_arn` | cloudfront, asg target group |
| `alb` | `target_group_arn` | asg |
| `alb` | `alb_dns_name` | route53, root output |
| `rds` | `cluster_endpoint` | app tier (환경변수로 주입) |
| `rds` | `reader_endpoint` | app tier |
| `elasticache` | `primary_endpoint` | app tier |

### 설계 팁
- output이 너무 많아지면 → `object` 타입으로 묶어서 노출하는 패턴도 있다
- 민감한 값(DB 패스워드 등)은 output으로 노출하지 말고 Secrets Manager를 통해 app이 직접 가져가게 한다

---

## 4. `modules/` vs `module/` 폴더명

Terraform 커뮤니티 관례는 **`modules/` (복수)** 이다.
HashiCorp 공식 예제, Terraform Registry 모두 `modules/`를 사용한다.

```
✅ modules/vpc/
❌ module/vpc/
```

---

## 5. 모듈 분리 vs State 분리 — 흔한 오개념

"모듈을 나누면 리소스가 각각 따로 생성되는 것 아닌가?" → **아니다.**

### 모듈 분리 = 코드 조직화

```
envs/dev/network/ 에서 terraform apply
  → module.network.aws_vpc.vpc
  → module.network.aws_subnet.public[*]    ← 전부
  → module.network.aws_nat_gateway.nat[*]  ← 하나의
  → module.network.aws_route_table.public  ← Plan으로 동시 생성
```

`modules/network/`가 아무리 여러 파일로 나뉘어 있어도, `envs/dev/network/`에서 `terraform apply`를 실행하면 **모든 리소스가 하나의 Plan으로 묶여서 동시에 처리**된다. 모듈은 코드를 파일로 나눈 것이고, 실행 단위는 `terraform apply`를 어느 폴더에서 실행하느냐로 결정된다.

**모듈을 분리하는 진짜 이유는 재사용이다.**
`modules/network/`를 한 번 잘 만들어두면 `envs/dev/`와 `envs/prod/` 양쪽이 같은 코드를 공유한다. 수정이 필요하면 한 곳만 고쳐도 양쪽에 반영된다.

### State 분리 = 진짜 "각각 생성"

레이어별로 별도 폴더에서 `terraform apply`를 실행하는 것이 진짜 독립 실행이다.

```
envs/dev/1-network/   → terraform apply  (State 파일 1)
envs/dev/2-security/  → terraform apply  (State 파일 2)
envs/dev/3-web/       → terraform apply  (State 파일 3)
```

각 폴더는 독립된 State를 가지므로 ALB 설정만 바꿀 때 VPC, RDS는 전혀 건드리지 않는다.

| 개념 | 목적 | 실행 단위 |
|------|------|---------|
| 모듈 분리 | 코드 재사용 | 영향 없음 — 같은 apply로 전부 생성 |
| State 분리 | 변경 범위 격리 | 레이어마다 독립 apply |

---

## 6. 모듈 인터페이스 설계 — 처음부터 컬렉션으로

모듈 변수는 **모듈의 public API**다. 한 번 여러 root module이 참조하기 시작하면, 타입 변경은 곧 breaking change가 된다.

```
modules/security/
    └── variables.tf  ← API 명세서

envs/dev/security/   ← API 호출자
envs/prod/security/  ← API 호출자
```

`var.sg_name = string` → `var.sg = map(object)` 로 바꾸면 모든 호출자를 동시에 수정해야 한다.

### 원칙: 복수 가능성이 있다면 처음부터 컬렉션으로

```hcl
# ❌ 나중에 여러 개가 필요해지면 breaking change
variable "iam_role_name" {
  type = string
}

# ✅ 처음부터 map으로 — 호출자는 항목 하나만 넘기면 됨
variable "iam_roles" {
  type = map(object({
    name = string
  }))
}
```

이 프로젝트에서 SG를 처음부터 `map(object)`로 설계한 것이 올바른 선택이었던 이유다.

### non-breaking 확장: optional() 활용

타입 자체를 바꾸지 않고, 기존 object에 선택 필드를 추가하는 방식으로 확장한다. Terraform 1.3+에서 지원.

```hcl
variable "iam_roles" {
  type = map(object({
    name        = string
    description = optional(string, null)  # 기존 호출자는 수정 불필요
  }))
}
```

### 모듈 인터페이스 설계 판단 기준

| 상황 | 권장 대응 |
|------|-----------|
| 처음 설계 시, 복수 가능성 있음 | 처음부터 `map(object)` |
| 필드 추가 필요 | `optional()` 로 non-breaking 확장 |
| 타입 자체를 바꿔야 함 | 불가피한 breaking change → 모든 호출자 동시 수정 |
| 모듈이 너무 비대해짐 | 별도 모듈로 분리 검토 |

---

## 관련 개념
- Provider Inheritance: https://developer.hashicorp.com/terraform/language/modules/develop/providers
- Terraform Style Guide: https://developer.hashicorp.com/terraform/language/style
- 검색 키워드: `terraform module provider inheritance`, `terraform module file structure`, `terraform state separation layers`
