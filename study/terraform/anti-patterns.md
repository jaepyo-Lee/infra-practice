# Terraform 안티패턴 & 개선 포인트

> 마지막 업데이트: 2026-03-07 (실무 코드 분석 기반 작성)
> 실무 코드에서 발견한 패턴들 — 이렇게 하면 나중에 고생한다

---

## 1. 루트 모듈이 너무 많은 것을 담당 (God Module)

### 문제

`prod/main.tf` 단일 파일이 아래를 전부 담당하고 있다:
- VPC / Subnet / NAT Gateway
- 5개의 ALB (public, private, admin-api, api, alpha)
- ECS Cluster
- Database (RDS, DocumentDB, ElastiCache)
- GitHub Actions IAM Role + Policy 5개

결과: 800줄이 넘는 파일 하나가 `prod/terraform.tfstate` 하나에 모두 들어간다.

```
prod/
  main.tf  ← 800줄 (VPC + ALB + ECS + DB + IAM 전부)
```

### 왜 나쁜가

1. **변경 범위 격리 불가**: ALB 설정 하나 바꾸려면 VPC, DB까지 같은 plan에 포함됨
2. **장애 범위 확대**: plan 오류 시 전체 환경에 영향
3. **plan 속도 저하**: 리소스가 많을수록 느림
4. **리뷰 어려움**: PR에서 무엇이 바뀌었는지 파악하기 어려움

### 개선 방향

레이어별로 State 분리:

```
prod/
  1-networking/
    main.tf   ← VPC, Subnet, NAT, Routes만 (State 1)
  2-security/
    main.tf   ← SG, IAM만 (State 2)
  3-alb/
    main.tf   ← ALB들만 (State 3)  ← 변경이 잦음, 독립 분리 이득 큼
  4-ecs-cluster/
    main.tf   ← ECS Cluster + Capacity Provider (State 4)
  5-database/
    main.tf   ← RDS, Redis (State 5)
  ecs/
    backend/  ← ECS Service (State 6)
    frontend/ ← ECS Service (State 7)
```

서비스를 추가할 때 `ecs/` 하위 폴더만 건드리고, 나머지 레이어는 건드릴 필요 없다.

---

## 2. ALB를 하나의 State에서 여러 서비스가 공유

### 문제

`prod/main.tf`에서 5개 ALB를 한꺼번에 관리하고, 각 ECS 서비스(`prod/ecs/backend/`, `prod/ecs/frontend/`)는 remote state로 ALB ARN을 참조한다.

```
prod/main.tf (State A)
  ├── alb_public   ← frontend가 참조
  ├── alb_private  ← backend가 참조
  ├── alb_api      ← backend가 참조
  └── alb_alpha    ← alpha 서비스가 참조

prod/ecs/backend/main.tf (State B)
  └── data.terraform_remote_state.base.outputs.alb_api_https_listener_arn
```

### 왜 나쁜가

1. **ALB 추가/수정 시 prod 전체 state를 건드려야 함**: backend 서비스를 위해 ALB를 추가하면 VPC, DB가 포함된 거대한 state를 변경
2. **유연성 부족**: 새 서비스용 ALB가 필요할 때 prod/main.tf를 수정하고, 이미 운영 중인 서비스에 영향을 줄 수 있음
3. **Output key 네이밍 의존성**: `alb_api_https_listener_arn`, `alb_public_security_group_id` 같은 string key로 동적 참조하는 방식은 오타 시 런타임에만 에러 발견

### 개선 방향

ALB를 서비스와 함께 또는 독립 레이어로 분리:

```
# 방법 A: ALB를 별도 레이어로
prod/3-alb/
  main.tf   ← 모든 ALB (networking과 ecs-cluster 사이 레이어)

# 방법 B: 서비스별로 ALB를 함께 관리 (소규모 서비스에 적합)
prod/ecs/backend/
  main.tf   ← backend ALB + ECS Service 함께
```

---

## 3. AWS Profile 하드코딩

### 문제

```hcl
# prod/main.tf
provider "aws" {
  profile = "next"  # ← 하드코딩
}

backend "s3" {
  profile = "next"  # ← 하드코딩
}
```

### 왜 나쁜가

1. **CI/CD에서 동작 안 함**: GitHub Actions 환경에는 `next` 프로파일이 없다. OIDC로 assume role하면 profile이 아니라 환경 변수로 인증
2. **다른 환경에서 재사용 불가**: dev/prod를 다른 AWS 계정으로 관리하면 profile 이름이 달라짐
3. **협업자 강제**: 팀원이 자신의 로컬 AWS CLI에 정확히 `next` profile을 설정해야만 동작

### 개선 방향

```hcl
# provider에서 profile 제거 → 환경 변수 또는 CI/CD OIDC로 인증
provider "aws" {
  region = var.aws_region
  # profile 없음 → AWS_PROFILE 환경 변수 또는 instance role로 자동 인증
}
```

```bash
# 로컬에서: 환경 변수로 지정
export AWS_PROFILE=next
terraform plan

# CI/CD: OIDC AssumeRole → 환경 변수 자동 주입 (profile 불필요)
```

`backend {}` 블록은 변수를 받을 수 없어서 profile을 넣으면 하드코딩이 된다. 해결책:

```bash
# partial backend config — profile을 CLI에서 주입
terraform init \
  -backend-config="profile=next" \
  -backend-config="bucket=my-state-bucket"
```

```hcl
# main.tf의 backend 블록 — profile 없이
backend "s3" {
  bucket  = "my-state-bucket"
  key     = "prod/terraform.tfstate"
  region  = "ap-northeast-2"
  encrypt = true
  # profile은 terraform init -backend-config로 주입
}
```

---

## 4. AWS 리소스 ID 하드코딩

### 문제

```hcl
# prod/main.tf
data "aws_security_group" "cloudshell_instance" {
  id = "sg-0172ce3f0b53fe671"  # ← SG ID 직접 하드코딩
}
```

### 왜 나쁜가

1. **환경 이식성 없음**: dev 환경의 CloudShell SG ID는 다르다. 코드를 dev에 복사하면 즉시 깨짐
2. **가독성 없음**: ID만 보고는 이게 무엇인지 알 수 없음
3. **리소스가 삭제/재생성되면 ID가 바뀜**: 코드를 다시 수정해야 함

### 개선 방향

```hcl
# 이름/태그로 동적 조회
data "aws_security_group" "cloudshell_instance" {
  filter {
    name   = "tag:Name"
    values = ["cloudshell-instance-sg"]
  }
  # 또는
  filter {
    name   = "group-name"
    values = ["cloudshell-${var.environment}-sg"]
  }
}
```

---

## 5. `project_name` 기본값 특정 프로젝트로 고정

### 문제

```hcl
# modules/ecs-service/variables.tf
variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "zippoom"  # ← 특정 프로젝트 이름 하드코딩
}
```

### 왜 나쁜가

모듈은 재사용 가능해야 한다. `default = "zippoom"` 이면:
1. 다른 프로젝트에서 이 모듈을 쓸 때 `project_name`을 항상 지정해야 한다는 것을 잊기 쉬움
2. 지정 안 하면 조용히 잘못된 이름으로 리소스가 생성됨

### 개선 방향

```hcl
variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  # default 없음 → 필수값으로 만들어 호출자가 반드시 지정하게 함
}
```

---

## 6. `depends_on` 과용

### 문제

```hcl
# prod/main.tf
module "compute" {
  depends_on = [module.networking, module.dns]
}

module "database" {
  depends_on = [module.networking, module.compute]
}
```

### 왜 나쁜가

Terraform은 실제 **속성 참조**를 통해 의존성을 자동으로 파악한다.

```hcl
module "compute" {
  vpc_id     = module.networking.vpc_id        # ← 이 참조가 있으면
  subnet_ids = module.networking.app_subnet_ids # ← 자동으로 networking 먼저 생성
}
```

위처럼 참조가 있으면 `depends_on = [module.networking]`은 **중복이자 소음**이다.

`depends_on`을 과하게 쓰면:
1. plan 그래프가 불필요하게 복잡해짐
2. 실제 의존 관계가 코드에서 명확히 보이지 않음
3. 불필요한 순차 실행 → plan/apply 속도 저하

### 개선 방향

`depends_on`은 **암묵적 의존성**(직접 참조가 없지만 실행 순서가 중요한 경우)에만 사용:

```hcl
# ✅ depends_on이 필요한 경우: 참조가 없지만 순서가 중요할 때
# 예: IAM Policy 생성 후에야 서비스가 해당 권한으로 API 호출 가능
resource "aws_ecs_service" "this" {
  depends_on = [aws_iam_role_policy.ecs_execution_secrets]
  # IAM Policy를 직접 참조하지는 않지만, 정책이 붙어야 실행 가능
}
```

---

## 7. `_shared/locals.json` 패턴의 함정

### 문제

```hcl
# prod/ecs/backend/locals.tf
locals {
  shared = jsondecode(file("${path.module}/../_shared/locals.json"))
  environment = local.shared.environment
}
```

```json
// prod/ecs/_shared/locals.json
{
  "aws_region": "ap-northeast-2",
  "project_name": "zippoom",
  "environment": "prod"
}
```

### 왜 나쁜가

1. **Terraform 변수 시스템 우회**: `variable`, `tfvars`로 관리하면 되는 것을 JSON 파일로 만들었음
2. **환경 분리 어려움**: `locals.json`에 `environment = "prod"` 하드코딩 → dev에서 쓰려면 파일 직접 수정
3. **검증 없음**: `variable` 블록의 `validation`이 동작하지 않음. 잘못된 값이 들어가도 plan 시점에 잡히지 않음
4. **`path.module` 의존**: 파일 위치가 바뀌면 경로를 모두 수정해야 함

### 개선 방향

```hcl
# ✅ Terraform 변수 시스템 사용
# prod/ecs/backend/terraform.tf
locals {
  aws_region   = "ap-northeast-2"
  project_name = "zippoom"
  environment  = "prod"
}

# 또는 variables.tf + prod.tfvars로 주입
```

단, `locals.json` 패턴이 **정당화**될 수 있는 경우:
- 환경과 무관한 상수 (예: 고정된 AMI 이름 목록, 리전별 설정 맵)
- Terraform이 아닌 다른 도구(Bash 스크립트 등)도 같은 값을 참조해야 할 때

---

## 8. 두 개의 유사한 모듈 공존 (modules/compute vs modules/ecs-service)

### 문제

```
modules/
  compute/         ← frontend 전용으로 만든 old 모듈
    alb.tf
    ecs-service.tf
    ecr.tf
    ...
  ecs-service/     ← 범용 모듈로 새로 만든 것
    ecs-service.tf
    ecs-task.tf
    ...
```

### 왜 나쁜가

1. **"어느 걸 써야 하나?" 혼란**: 새 서비스 추가 시 어떤 모듈을 써야 하는지 알 수 없음
2. **중복 유지보수**: 같은 기능의 버그를 두 곳에서 각각 고쳐야 함
3. **기능 불균형**: `ecs-service`에 추가된 기능(Circuit Breaker, Service Connect 등)이 `compute`에는 없음

### 개선 방향

1. `compute` 모듈 사용처를 `ecs-service` 모듈로 마이그레이션
2. 마이그레이션 완료 후 `compute` 모듈 삭제
3. 과도기에는 `DEPRECATED.md`를 `compute/`에 남겨 팀원에게 안내

---

## 9. `lifecycle { ignore_changes }` 범위가 너무 넓음

### 문제

```hcl
resource "aws_ecs_service" "this" {
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition,
      force_new_deployment,
      capacity_provider_strategy,
      network_configuration,           # ← 보안 관련 설정
      health_check_grace_period_seconds,
      deployment_maximum_percent,
      deployment_minimum_healthy_percent,
      service_connect_configuration,
    ]
  }
}
```

`network_configuration`을 ignore하면 Security Group이 바뀌어도 Terraform이 감지하지 못한다.
`deployment_maximum_percent`, `deployment_minimum_healthy_percent`를 ignore하면 배포 설정을 코드로 관리 불가.

### 개선 방향

`ignore_changes`는 **외부 도구(CI/CD, Auto Scaling)가 관리하는 속성**에만 한정:

```hcl
lifecycle {
  ignore_changes = [
    desired_count,    # Auto Scaling이 관리
    task_definition,  # CI/CD가 관리
    # 그 외 Terraform이 관리해야 할 설정은 ignore하지 않음
  ]
}
```

---

## 10. `host_header`에 Wildcard 사용

### 문제

```hcl
# prod/ecs/backend/main.tf
module "backend" {
  host_header = "*.zippo-om.com"  # ← 와일드카드
}
```

ALB Listener Rule에서 `*.zippo-om.com`을 허용하면 해당 도메인의 **모든 서브도메인**이 이 서비스로 라우팅된다.

### 왜 나쁜가

1. **보안**: 의도치 않은 서브도메인도 라우팅됨 (예: `malicious.zippo-om.com` → 내 backend)
2. **예측 불가**: 어떤 요청이 올지 명확하지 않음

### 개선 방향

```hcl
# ✅ 명시적 서브도메인 지정
host_header = "api.zippo-om.com"

# 여러 개가 필요하면 list로
host_headers = ["api.zippo-om.com", "api-v2.zippo-om.com"]
```

---

## 11. 모듈 output 설계 — 하드코딩 named output vs 맵 전체 노출

### 두 가지 방식

**Named output (하드코딩)**
```hcl
output "alb_sg_id" {
  value = aws_security_group.sg["alb_sg"].id
}
output "app_sg_id" {
  value = aws_security_group.sg["app_sg"].id
}
```

**맵 전체 노출**
```hcl
output "sg_ids" {
  value = { for k, v in aws_security_group.sg : k => v.id }
}
# 호출 측: module.security.sg_ids["alb_sg"]
```

### 언제 무엇을 쓰는가

| 상황 | 추천 방식 | 이유 |
|------|-----------|------|
| 리소스 구성이 고정 (항상 3개) | Named output | 명시적, IDE 자동완성 지원 |
| 리소스가 늘어날 수 있음 | 맵 전체 노출 | 추가 시 outputs.tf 수정 불필요 |
| 범용 모듈 (여러 팀/프로젝트 재사용) | 맵 전체 노출 | 호출자가 필요한 것만 꺼내 씀 |

### 핵심 원칙

어떤 방식이든 **특정 키 이름은 어딘가에 하드코딩된다**. 차이는 그 위치다.

- Named output → 모듈 내부(`outputs.tf`)에 고정. 키가 없으면 모듈 자체가 에러
- 맵 노출 → 호출 측에 고정. 모듈은 범용성 유지, 키가 없으면 호출 측에서 에러

SG처럼 환경마다 추가될 수 있는 리소스는 **맵 전체 노출**이 유지보수에 유리하다.

---

## 12. `terraform {}` 블록을 리소스 파일에 혼재

### 문제

```hcl
# modules/web/alb.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"   # ← 다른 파일/레이어와 다른 버전
    }
  }
}

resource "aws_lb" "alb" { ... }  # ← 리소스와 섞임
```

### 왜 나쁜가

1. **버전 충돌**: 호출자(envs/)가 `~> 5.0`을 쓰는데 모듈이 `6.17.0`을 선언하면 두 constraint를 동시에 만족하는 버전이 없음 → `terraform init` 실패
2. **발견 어려움**: `alb.tf` 안에 숨어 있어 버전이 어디서 왔는지 추적하기 어려움
3. **관심사 혼재**: `alb.tf`는 ALB 리소스를 정의하는 파일. Terraform 메타 설정이 섞이면 파일의 역할이 불명확해짐

### 올바른 방법

`terraform {}` 블록 (required_providers, required_version)은 **반드시 `versions.tf`로 분리**:

```
modules/web/
  versions.tf   ← terraform { required_providers {} } 여기에만
  alb.tf        ← resource만
  cloudfront.tf ← resource만
```

```hcl
# modules/web/versions.tf
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.us_east_1]  # alias 선언도 여기에
    }
  }
}
```

### 버전 통일 전략

여러 레이어/모듈에서 버전 constraint가 달라 충돌할 때:

| 상황 | 선택 |
|------|------|
| 하나만 다른 버전 | 그 하나를 내려서 전체 통일 |
| 전체를 새 버전으로 올리려는 경우 | 모든 파일 동시 업데이트 후 `terraform init -upgrade` |
| 보안 패치/버그픽스가 새 버전에 있는 경우 | 올리는 것 고려 |

---

## 요약 — 체크리스트

내 코드에 아래 패턴이 있는지 확인:

| 체크 항목 | 안티패턴 | 개선 방향 |
|-----------|---------|---------|
| prod/main.tf 줄 수 | 500줄 이상 | 레이어별 State 분리 |
| ALB 위치 | 기반 인프라와 동일 State | 독립 레이어 또는 서비스와 함께 |
| provider profile | 코드에 하드코딩 | 환경 변수 또는 partial backend config |
| 리소스 ID | 코드에 직접 명시 | data source + filter로 동적 조회 |
| project_name 기본값 | 특정 값 하드코딩 | 기본값 없이 필수값으로 |
| depends_on | 참조가 있는데 추가 | 참조가 있으면 제거, 암묵적 의존에만 사용 |
| 공유 상수 | JSON 파일 + file() | locals {} 또는 variable + tfvars |
| ignore_changes | 보안/배포 설정 포함 | CI/CD, Auto Scaling 관리 속성만 |
| host_header | 와일드카드 | 명시적 도메인 |
| `terraform {}` 위치 | 리소스 파일에 혼재 | `versions.tf`로 분리 |
| provider 버전 | 레이어/모듈마다 다름 | 전체 통일, 하나만 튀면 내려서 맞춤 |

---

## 관련 파일

- [module-structure.md](./module-structure.md) — 모듈 설계 원칙
- [remote-state.md](./remote-state.md) — State 분리 아키텍처
- [lifecycle-and-import.md](./lifecycle-and-import.md) — ignore_changes 올바른 사용법
