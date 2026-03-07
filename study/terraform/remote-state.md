# Terraform Remote State & 멀티 State 아키텍처

> 마지막 업데이트: 2026-03-07 (실무 코드 분석 기반 작성)

---

## 1. 왜 필요한가

Terraform State를 하나로 관리하면 리소스가 많아질수록 `plan/apply`가 느려지고, 작은 변경 하나가 전체 인프라에 영향을 줄 수 있다.

실무에서는 **레이어별, 서비스별로 State를 분리**하고, 다른 State의 output을 참조하는 방식을 쓴다.

```
prod/terraform.tfstate          ← VPC, ALB, ECS 클러스터 (기반 환경)
prod/ecs/backend/terraform.tfstate  ← backend 서비스만
prod/ecs/frontend/terraform.tfstate ← frontend 서비스만
global/terraform.tfstate        ← ACM 인증서, OIDC Provider 등 (전역 리소스)
```

**장점:**
- backend 서비스만 배포할 때 frontend, DB는 전혀 건드리지 않음
- plan 속도 향상 (리소스 수 적음)
- 실수로 다른 레이어를 삭제할 위험 없음

---

## 2. `terraform_remote_state` — 다른 State 참조하기

`data "terraform_remote_state"` 는 다른 State 파일의 `output`을 읽어오는 data source다.

```hcl
# prod/ecs/backend/main.tf
data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket  = "my-terraform-state"
    key     = "prod/terraform.tfstate"   # 참조할 State 파일 경로
    region  = "ap-northeast-2"
    profile = "my-aws-profile"
  }
}

# 사용 - base State의 output을 참조
vpc_id         = data.terraform_remote_state.base.outputs.vpc_id
app_subnet_ids = data.terraform_remote_state.base.outputs.app_subnet_ids
ecs_cluster_arn = data.terraform_remote_state.base.outputs.ecs_cluster_arn
```

**핵심 조건:** 참조하려는 값이 원본 State의 `outputs.tf`에 반드시 선언되어 있어야 한다. output에 없으면 참조 불가.

---

## 3. `count`를 이용한 조건부 참조

Remote state를 항상 참조하면 해당 State가 없을 때 에러가 난다. `count`로 조건부 참조한다.

```hcl
# global remote state는 필요할 때만 참조
data "terraform_remote_state" "global" {
  count   = var.use_global_remote_state || var.create_route53_record ? 1 : 0
  backend = "s3"

  config = {
    bucket = "my-terraform-state"
    key    = "global/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# 사용 시 - [0] 인덱스로 접근
hosted_zone_id = try(data.terraform_remote_state.global[0].outputs.hosted_zone_id, null)
```

`try()`로 감싸면 값이 없을 때 null을 반환해 에러를 방지한다.

---

## 4. 실무 패턴: locals에서 remote state 값 정리

remote state 값을 locals로 한 번 정리해두면, 이후 참조가 훨씬 깔끔해진다.

```hcl
locals {
  base_outputs = data.terraform_remote_state.base.outputs

  # Remote state 기본값, 하지만 직접 지정한 변수가 있으면 그게 우선 (coalesce 패턴)
  vpc_id         = coalesce(var.vpc_id, local.base_outputs.vpc_id)
  app_subnet_ids = coalesce(var.app_subnet_ids, local.base_outputs.app_subnet_ids)
  ecs_cluster_arn = coalesce(var.ecs_cluster_arn, local.base_outputs.ecs_cluster_arn)
}
```

`coalesce(a, b)` = a가 null이 아니면 a, null이면 b. Override 패턴의 핵심이다.

**장점:** 모듈을 두 가지 방식으로 쓸 수 있다.
1. remote state에서 자동으로 값 참조 (var 기본값 null)
2. 직접 var로 지정 (테스트, 예외 상황)

---

## 5. 동적 Output Key 참조

실무 코드에서 발견한 고급 패턴. ALB 이름에 따라 동적으로 output key를 참조한다.

```hcl
locals {
  # alb_name = "public" → "alb_public_https_listener_arn" key를 동적으로 생성
  # alb_name = "private" → "alb_private_https_listener_arn"
  alb_name_normalized = replace(var.alb_name, "-", "_")  # 하이픈 → 언더스코어

  listener_arn = try(
    coalesce(
      var.listener_arn,
      local.base_outputs["alb_${local.alb_name_normalized}_https_listener_arn"]
    ),
    null
  )
}
```

`local.base_outputs["key_name"]` — map처럼 대괄호로 동적 key 참조 가능.
`"alb_${local.alb_name_normalized}_https_listener_arn"` — 문자열 보간으로 key를 동적 생성.

이 패턴 덕분에 모듈을 호출할 때 `alb_name = "api"`만 지정하면 모듈이 알아서 올바른 ALB를 찾는다.

---

## 6. State 분리 전략 — 실무 구조

실무 프로젝트에서 실제로 사용하는 State 분리 구조:

```
terraform/
  environments/
    global/                        ← global/terraform.tfstate
      main.tf                      # ACM 인증서, GitHub OIDC Provider (전역 리소스)
    prod/                          ← prod/terraform.tfstate
      main.tf                      # VPC, ALB, ECS 클러스터 (기반 인프라)
    prod/ecs/
      backend/                     ← prod/ecs/backend/terraform.tfstate
        main.tf                    # backend ECS 서비스만
      frontend/                    ← prod/ecs/frontend/terraform.tfstate
        main.tf                    # frontend ECS 서비스만
      scheduler/                   ← prod/ecs/scheduler/terraform.tfstate
        main.tf                    # scheduler ECS 서비스만
```

**참조 방향은 단방향이어야 한다:**
```
global ← prod ← prod/ecs/backend
```
- backend가 prod를 참조하는 것은 OK
- prod가 backend를 참조하는 것은 NG (순환 참조)

---

## 7. `_shared/locals.json` 패턴

여러 서비스에서 공통으로 쓰는 상수(region, project_name, environment)를 JSON 파일로 공유하는 패턴.

```
prod/ecs/
  _shared/
    locals.json    ← { "aws_region": "ap-northeast-2", "project_name": "zippoom", "environment": "prod" }
  backend/
    locals.tf      ← locals { shared = jsondecode(file("${path.module}/../_shared/locals.json")) }
  frontend/
    locals.tf      ← 동일
```

```hcl
# backend/locals.tf
locals {
  shared       = jsondecode(file("${path.module}/../_shared/locals.json"))
  aws_region   = local.shared.aws_region
  project_name = local.shared.project_name
  environment  = local.shared.environment
}
```

`file()` 함수: 지정한 파일을 문자열로 읽는다.
`jsondecode()` 함수: JSON 문자열을 Terraform 객체로 파싱한다.
`${path.module}`: 현재 .tf 파일이 있는 디렉토리 경로.

---

## 8. Remote State vs 직접 데이터 소스 조회

| 상황 | 권장 방법 |
|------|---------|
| 내가 Terraform으로 만든 리소스 참조 | `terraform_remote_state` |
| 콘솔에서 만든 기존 리소스 참조 | `data "aws_xxx"` (직접 조회) |
| 이름/태그로 검색해야 하는 경우 | `data "aws_xxx"` + filter |

```hcl
# 실무 예시: Terraform으로 만들지 않은 Security Group 조회
data "aws_security_group" "backend_ecs_tasks" {
  filter {
    name   = "group-name"
    values = ["my-project-prod-backend-ecs-tasks-sg"]
  }
}

# 특정 ID로 직접 조회
data "aws_security_group" "cloudshell_instance" {
  id = "sg-0172ce3f0b53fe671"
}
```

---

## 관련 파일

- [core-blocks.md](./core-blocks.md) — output 블록 작성법
- [backend.md](./backend.md) — S3 Remote Backend 설정

**검색 키워드:** `terraform remote state data source`, `terraform state separation strategy`, `terraform_remote_state outputs`
