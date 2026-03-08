# Terraform 함수 & 표현식 실전 패턴

> 마지막 업데이트: 2026-03-07 (실무 코드 분석 기반 작성)

---

## 1. 왜 필요한가

Terraform은 단순한 설정 파일이 아니라 표현식과 함수를 지원하는 언어다.
실무 코드에서 반드시 만나게 되는 함수들과 패턴을 정리한다.

---

## 2. `coalesce()` — 첫 번째 null이 아닌 값 반환

```hcl
coalesce(val1, val2, val3, ...)
```

앞에서부터 순서대로 평가해서 null이 아닌 첫 번째 값을 반환한다.
빈 문자열(`""`)도 null로 취급하지 않으므로 주의.

**실무 패턴: Override 패턴**

```hcl
locals {
  # var.vpc_id가 null이면 remote state에서 가져옴
  # var.vpc_id가 지정되면 그게 우선
  vpc_id = coalesce(var.vpc_id, data.terraform_remote_state.base.outputs.vpc_id)
}
```

모듈을 만들 때 "기본값은 remote state에서, 필요하면 직접 지정"하는 flexible한 인터페이스를 만들 수 있다.

---

## 3. `try()` — 에러 시 fallback 값 반환

```hcl
try(expression, fallback_value)
```

expression을 평가하다 에러가 나면 에러를 내지 않고 fallback_value를 반환한다.
존재하지 않을 수 있는 값에 접근할 때 사용한다.

```hcl
# remote state에 해당 output이 없을 수도 있는 경우
listener_arn = try(
  coalesce(
    var.listener_arn,
    local.base_outputs["alb_${local.alb_name_normalized}_https_listener_arn"]
  ),
  null  # 에러 발생 시 null 반환
)
```

**`try()` vs null check:**
```hcl
# try(): 속성 접근 자체가 에러날 수 있을 때 (key가 없는 map 접근 등)
value = try(some_map["maybe_missing_key"], null)

# 단순 null check: 속성이 있지만 값이 null일 수 있을 때
value = var.something != null ? var.something : "default"
```

---

## 4. `dynamic` 블록 — 조건부 중첩 블록 생성

Terraform에서 `count`/`for_each`는 리소스 단위에만 쓸 수 있다.
리소스 **내부의 중첩 블록**을 조건부로 생성하려면 `dynamic`을 써야 한다.

```hcl
resource "aws_lb" "this" {
  # ...

  # access_logs_bucket이 null이 아닐 때만 access_logs 블록 생성
  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      enabled = true
    }
  }
}
```

**패턴: 조건부 블록 생성**
```hcl
dynamic "블록이름" {
  for_each = 조건 ? [1] : []   # 조건이 true면 블록 1개 생성, false면 0개
  content {
    # 블록 내용
  }
}
```

**패턴: 리스트로 여러 블록 생성**
```hcl
# load_balancer 블록을 여러 개 동적으로 생성
dynamic "load_balancer" {
  for_each = local.load_balancer_configs  # list of objects
  content {
    target_group_arn = load_balancer.value.target_group_arn
    container_name   = load_balancer.value.container_name
    container_port   = load_balancer.value.container_port
  }
}
```

`load_balancer.value` — `for_each`의 현재 아이템에 접근하는 방법.
iterator 이름은 블록 이름(`load_balancer`)이 기본이고, `iterator = "별칭"` 으로 바꿀 수 있다.

**이 프로젝트 실사용 예시 (modules/web/alb.tf)**
```hcl
# certificate_arn이 있을 때만 redirect 블록 생성
resource "aws_lb_listener" "http" {
  default_action {
    type = var.certificate_arn != null ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}
```

**`dynamic` vs `count`/`for_each` 차이**

| | `count` / `for_each` | `dynamic` |
|---|---|---|
| 반복 대상 | 리소스 전체 | 리소스 내부 블록 |
| 예시 | EC2 3개, SG 5개 | ingress 규칙 여러 개, redirect 조건부 |
| 위치 | resource 선언 밖 | resource 블록 안 |

---

## 5. `for` 표현식 — 컬렉션 변환

리스트/맵을 다른 형태로 변환한다.

**리스트 변환:**
```hcl
# endpoint_subnet_indexes = [0, 1]
# ecs 서브넷 중 0번, 1번 인덱스의 ID만 추출
subnet_ids = [for idx in var.endpoint_subnet_indexes : aws_subnet.ecs[idx].id]
# → ["subnet-aaa", "subnet-bbb"]
```

**map to list:**
```hcl
# map의 key만 추출
names = [for k, v in var.services : k]

# 조건부 필터
prod_services = [for k, v in var.services : k if v.environment == "prod"]
```

**list to map (for_each에서 자주 사용):**
```hcl
# 리스트를 map으로 변환해서 for_each에 사용
# → key가 name인 map
for_each = { for idx, policy in var.custom_scaling_policies : policy.name => policy }
```

`for_each`에 list를 직접 넣으면 안 된다. **반드시 map이나 set이어야 한다.** list를 쓰고 싶으면 위처럼 map으로 변환한다.

---

## 6. `jsonencode()` — HCL 객체를 JSON 문자열로

IAM Policy, ECS Container Definition 등 AWS가 JSON으로 받는 값을 작성할 때 사용.
직접 JSON 문자열을 쓰는 것보다 HCL 객체로 작성하면 타입 검증, 변수 참조가 가능하다.

```hcl
# ECS Container Definition
container_definitions = jsonencode([
  {
    name      = var.service_name
    image     = local.container_image_url
    essential = true

    portMappings = [
      {
        containerPort = var.container_port
        protocol      = "tcp"
      }
    ]

    # 변수 참조 가능
    environment = var.environment_variables
  }
])

# IAM Policy
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Action    = "sts:AssumeRole"
    Principal = { Service = "ecs-tasks.amazonaws.com" }
  }]
})
```

**jsonencode vs heredoc JSON:**
```hcl
# ❌ 문자열 heredoc - 변수 참조 불가, 타입 검증 없음
policy = <<EOF
{
  "Version": "2012-10-17"
}
EOF

# ✅ jsonencode - 변수 참조, 타입 검증 가능
policy = jsonencode({
  Version = "2012-10-17"
})
```

---

## 7. `variable` 검증 블록 — validation

모듈을 잘못 사용하는 것을 조기에 잡아준다. `plan` 시점에 에러가 나서 apply까지 가지 않아도 된다.

```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment는 'dev', 'staging', 'prod' 중 하나여야 합니다."
  }
}

variable "cpu" {
  type = number

  validation {
    condition     = contains([0.25, 0.5, 1, 2, 4], var.cpu)
    error_message = "cpu는 Fargate 지원 값(0.25, 0.5, 1, 2, 4)이어야 합니다."
  }
}
```

**언제 쓰는가:**
- 허용값이 정해져 있는 경우 (enum)
- 숫자 범위를 제한하고 싶을 때
- 여러 변수 간 의존 관계가 있을 때 (예: `create_ecr=false`이면 `container_image` 필수)

---

## 8. `optional()` — complex type의 선택 필드

Terraform 1.3+. `object` 타입 변수에서 일부 필드를 선택적으로 만들고 기본값도 지정할 수 있다.

```hcl
variable "additional_load_balancers" {
  type = list(object({
    target_group_arn = string           # 필수
    container_name   = optional(string) # 선택 (기본값 null)
    container_port   = optional(number) # 선택 (기본값 null)
  }))
  default = []
}
```

```hcl
variable "custom_scaling_policies" {
  type = list(object({
    name               = string
    target_value       = number
    scale_in_cooldown  = optional(number, 300)  # 기본값 300
    scale_out_cooldown = optional(number, 60)   # 기본값 60
  }))
}
```

**기존 모듈에 필드 추가 시 non-breaking change:**
```hcl
# 기존 호출자 코드를 수정하지 않아도 됨
variable "config" {
  type = object({
    name        = string
    description = optional(string, "")  # 신규 추가 필드
  })
}
```

---

## 9. `provider default_tags` — 모든 리소스에 태그 자동 적용

provider 레벨에서 `default_tags`를 설정하면, 그 provider로 만드는 모든 리소스에 자동으로 태그가 붙는다.

```hcl
provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "infrastructure"
    }
  }
}
```

**장점:** 리소스마다 `tags = { Project = "..." }` 반복 불필요.
**주의:** `default_tags`와 리소스의 `tags`가 같은 key를 가지면 리소스 `tags`가 우선한다.

리소스에서 추가 태그를 붙이고 싶을 때:
```hcl
resource "aws_ecs_cluster" "this" {
  name = "my-cluster"

  # default_tags에 없는 태그만 추가
  tags = {
    Name = "my-cluster"  # Name 태그는 리소스별로 다르므로 여기서 지정
  }
}
```

---

## 10. `data "aws_ssm_parameter"` — 최신 AMI 자동 조회

AMI ID를 하드코딩하지 않고 AWS SSM Parameter Store에서 최신 값을 가져오는 패턴.

```hcl
# ECS Optimized AMI (Amazon Linux 2023)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "this" {
  image_id = data.aws_ssm_parameter.ecs_ami.value
  # ...

  # AMI는 AWS가 주기적으로 업데이트함
  # 하지만 운영 중 인스턴스는 갑자기 교체되면 안 되므로 ignore
  lifecycle {
    ignore_changes = [image_id]
  }
}
```

**자주 쓰는 SSM Parameter 경로:**
```
/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id
/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
/aws/service/eks/optimized-ami/1.29/amazon-linux-2/recommended/image_id
```

---

## 11. `data.aws_caller_identity` / `data.aws_partition` 패턴

IAM Policy ARN에 Account ID를 동적으로 넣을 때 하드코딩을 피하는 패턴.

```hcl
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ARN에 계정 ID 동적 삽입
resource "aws_iam_role_policy" "example" {
  policy = jsonencode({
    Statement = [{
      Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
    }]
  })
}

# aws_partition 사용 이유: GovCloud는 partition이 "aws-us-gov"
# 하드코딩 "arn:aws:..." 은 GovCloud에서 깨짐
resource "aws_iam_role_policy_attachment" "example" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSTaskExecutionRolePolicy"
}
```

---

## 관련 파일

- [remote-state.md](./remote-state.md) — coalesce + try를 활용한 remote state 참조
- [core-blocks.md](./core-blocks.md) — variable, output, resource 기본 블록
- [lifecycle-and-import.md](./lifecycle-and-import.md) — lifecycle 메타인수

**검색 키워드:** `terraform coalesce function`, `terraform dynamic block`, `terraform for expression`, `terraform jsonencode`, `terraform validation block`
