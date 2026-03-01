# Terraform 핵심 블록: resource, variable, output, module

마지막 업데이트: 2026-03-01 (each.key/each.value 설명 추가)

---

## 한 줄 요약 — 프로그래밍 함수 비유

```
module   ≈  함수 호출
variable ≈  함수 파라미터 (입력)
resource ≈  함수 본문 (실제 동작)
output   ≈  함수 리턴값 (출력)
```

---

## 1. `resource` — 실제 AWS 인프라를 만드는 블록

Terraform의 가장 기본 단위. 이 블록이 실행되면 AWS에 실제 리소스가 생성된다.

```hcl
resource "aws_vpc" "main" {
#         ↑           ↑
#    리소스 타입   로컬 이름(Terraform 내부에서만 사용)
  cidr_block = "10.0.0.0/16"
}
```

- **리소스 타입** (`aws_vpc`): Provider가 어떤 AWS API를 호출할지 결정
- **로컬 이름** (`main`): 같은 코드 내에서 이 리소스를 참조할 때 사용하는 식별자
- **참조 방법**: `aws_vpc.main.id` → "타입.이름.속성" 형태

---

## 2. `variable` — 외부에서 값을 주입받는 입구

하드코딩 대신 외부에서 값을 받기 위한 블록. 모듈을 재사용 가능하게 만드는 핵심.

```hcl
# variables.tf
variable "cidr" {
  type        = string
  description = "VPC CIDR 블록"
  default     = "10.0.0.0/16"  # 없으면 호출자가 반드시 값을 제공해야 함
}
```

모듈 내부에서는 `var.변수명`으로 참조:

```hcl
# main.tf
resource "aws_vpc" "main" {
  cidr_block = var.cidr  # 외부에서 주입된 값 사용
}
```

### 왜 필요한가?
`cidr_block = "10.0.0.0/16"` 하드코딩 → dev/prod 환경에서 같은 모듈 재사용 불가
`var.cidr` 사용 → dev: `"10.0.0.0/16"`, prod: `"172.16.0.0/16"` 각각 주입 가능

### variable 속성
| 속성 | 필수 | 설명 |
|------|------|------|
| `type` | 권장 | string, number, bool, list, map, object 등 |
| `description` | 권장 | 이 변수가 무엇인지 설명 |
| `default` | 선택 | 기본값. 없으면 호출 시 반드시 값 제공 필요 |
| `validation` | 선택 | 입력값 검증 규칙 |

---

## 3. `output` — 모듈이 외부로 내보내는 값

모듈 내부 리소스의 속성을 **다른 모듈이 참조할 수 있도록** 노출하는 블록.

```hcl
# outputs.tf
output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id  # resource에서 생성된 값을 외부로 노출
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}
```

### 왜 필요한가?
- `modules/vpc/`가 VPC를 만들면, `modules/security_groups/`는 그 VPC ID가 필요하다
- security_groups 모듈은 vpc 모듈 내부를 직접 들여다볼 수 없다
- vpc 모듈이 `output "vpc_id"`로 값을 노출해야 security_groups가 받아서 쓸 수 있다

### output 참조 방법
```hcl
module.vpc.vpc_id          # "module.모듈이름.output이름"
module.vpc.public_subnet_ids
```

---

## 4. `module` — 다른 모듈을 호출하는 블록

재사용 가능한 모듈을 불러와 사용하는 블록. 함수 호출과 동일한 구조.

```hcl
# envs/dev/main.tf
module "vpc" {
  source = "../../modules/vpc"  # 모듈 경로 (필수)

  # variable에 값을 주입 (함수 인자 전달)
  name = "my-project"
  cidr = "10.0.0.0/16"
  tags = { Environment = "dev" }
}

# vpc 모듈의 output을 다른 모듈의 variable로 전달
module "security_groups" {
  source = "../../modules/security_groups"

  vpc_id = module.vpc.vpc_id  # ← vpc output → sg variable
}
```

---

## 5. 전체 데이터 흐름

```
envs/dev/main.tf
│
├── module "vpc" { cidr = "10.0.0.0/16" }
│         │
│         └── modules/vpc/
│               ├── variables.tf  ← cidr 받음
│               ├── main.tf       ← aws_vpc.main 생성
│               └── outputs.tf    ← vpc_id, subnet_ids 노출
│
└── module "security_groups" {
      vpc_id = module.vpc.vpc_id  ← vpc output → sg variable
    }
              │
              └── modules/security_groups/
                    ├── variables.tf  ← vpc_id 받음
                    ├── main.tf       ← aws_security_group 생성
                    └── outputs.tf    ← sg_ids 노출
```

**핵심 패턴**: 한 모듈의 `output` → 다른 모듈의 `variable`로 연결

---

## 6. 이 프로젝트에서의 적용

| 개념 | 위치 | 내용 |
|------|------|------|
| `resource` | `modules/vpc/main.tf` | `aws_vpc`, `aws_subnet`, `aws_internet_gateway` 등 |
| `variable` | `modules/vpc/variables.tf` | name, cidr, azs, tags 등 입력 |
| `output` | `modules/vpc/outputs.tf` | vpc_id, subnet_ids → 다른 모듈에 전달 |
| `module` | `envs/dev/main.tf` | vpc, sg, alb 등 모듈 조합해서 전체 인프라 구성 |

> 각 모듈별 파일 구조 컨벤션 및 outputs.tf에 담아야 할 목록 → [module-structure.md](./module-structure.md) 참고

---

## 7. 자주 하는 실수

### variable에 default 남용
```hcl
# ❌ 환경마다 달라야 하는 값에 default 설정
variable "instance_type" {
  default = "t3.micro"  # prod에서도 t3.micro가 될 수 있음
}

# ✅ default 없이 강제로 값을 받게 만들기
variable "instance_type" {
  type        = string
  description = "EC2 인스턴스 타입"
  # default 없음 → 호출자가 반드시 제공해야 함
}
```

### output을 안 만들고 하드코딩으로 대체
```hcl
# ❌ 다른 모듈에서 VPC ID를 하드코딩
resource "aws_security_group" "app" {
  vpc_id = "vpc-0abc123"  # 절대 하드코딩 금지
}

# ✅ module output으로 동적 참조
resource "aws_security_group" "app" {
  vpc_id = module.vpc.vpc_id
}
```

---

---

## 8. output은 child module에도 있다 (오개념 교정)

**오개념**: output은 root module에만 있는 것이다.
**정정**: output은 어디서든 선언할 수 있다. child module의 output이 오히려 더 핵심적인 역할을 한다.

### output 위치별 역할

| 위치 | 노출 대상 | 참조 방법 |
|------|-----------|-----------|
| `modules/vpc/outputs.tf` (child) | 자기를 호출한 모듈 | `module.vpc.vpc_id` |
| `envs/dev/main.tf` (root) | 사람 / 외부 도구 / 다른 state | `terraform output` 명령 |

child module은 output 없이는 값을 밖으로 내보낼 수 없다. output이 없으면 그 모듈 내부의 리소스 속성은 외부에서 절대 참조 불가다.

### root module output을 쓰는 경우

**1. `terraform output` 명령으로 배포 결과 확인**
```bash
$ terraform output
alb_dns_name = "my-alb-123456.ap-northeast-2.elb.amazonaws.com"
rds_endpoint = "my-db.cluster-xyz.ap-northeast-2.rds.amazonaws.com"
```

**2. 다른 Terraform state에서 참조 (`remote_state`)**
```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config  = { bucket = "my-tfstate", key = "dev/network.tfstate" }
}

resource "aws_instance" "app" {
  subnet_id = data.terraform_remote_state.network.outputs.private_subnet_id
}
```

**3. CI/CD 파이프라인에서 값 추출**
```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
# Route53 업데이트, 헬스체크 URL 구성 등에 활용
```

root module output은 선택사항. child module output은 모듈 간 연결을 위해 필수.

---

## 9. module 이름(label)이 식별자다

같은 모듈을 여러 번 호출할 때 **module 블록의 이름**으로 구분한다.

```hcl
module "vpc_app" {           # 이름: vpc_app
  source = "../../modules/vpc"
  cidr   = "10.0.0.0/16"
}

module "vpc_mgmt" {          # 이름: vpc_mgmt (같은 모듈, 다른 이름)
  source = "../../modules/vpc"
  cidr   = "192.168.0.0/16"
}

# 참조 시 이름으로 구분
module.vpc_app.vpc_id
module.vpc_mgmt.vpc_id
```

같은 이름 두 번 → **문법 에러 (Duplicate module call)**

### scope — 이름이 유일해야 하는 범위

**같은 폴더(디렉토리) = 같은 scope**

Terraform은 폴더 하나를 하나의 설정 단위로 인식한다. 폴더 안의 모든 `.tf` 파일을 합쳐서 읽는다.

```
envs/dev/        ← 이 폴더 전체가 하나의 scope
  main.tf        ← module "vpc" 선언
  network.tf     ← module "vpc" 또 선언하면 에러
```

**다른 폴더 = 다른 scope → 이름 중복 무관**

```
envs/dev/main.tf   → module "vpc" { ... }   # 독립적
envs/prod/main.tf  → module "vpc" { ... }   # 독립적, 충돌 없음
```

---

## 10. `for_each`로 같은 모듈 여러 개 생성

수가 많거나 동적으로 결정될 때 `for_each` 사용.

```hcl
module "vpc" {
  for_each = {
    app  = "10.0.0.0/16"
    mgmt = "192.168.0.0/16"
  }
  source = "../../modules/vpc"
  cidr   = each.value
}

# 참조 시 key로 구분
module.vpc["app"].vpc_id
module.vpc["mgmt"].vpc_id
```

### state 저장 형태 비교

| 방식 | state key 형태 |
|------|---------------|
| 일반 module 블록 | `module.vpc_app.aws_vpc.main` |
| for_each | `module.vpc["app"].aws_vpc.main` |

### `each` 객체 — for_each 블록 안에서만 쓸 수 있는 특수 객체

`for_each`에 맵을 넣으면, 각 반복마다 Terraform이 `each` 객체를 자동으로 제공한다.

```hcl
resource "aws_subnet" "public" {
  for_each = {
    "ap-northeast-2a" = "10.0.1.0/24"
    "ap-northeast-2c" = "10.0.2.0/24"
  }

  availability_zone = each.key    # 맵의 키: "ap-northeast-2a" 또는 "ap-northeast-2c"
  cidr_block        = each.value  # 맵의 값: "10.0.1.0/24" 또는 "10.0.2.0/24"
}
```

| 반복 | `each.key` | `each.value` |
|------|-----------|-------------|
| 1번째 | `"ap-northeast-2a"` | `"10.0.1.0/24"` |
| 2번째 | `"ap-northeast-2c"` | `"10.0.2.0/24"` |

- `each.key` = 이번 반복의 **맵 키**
- `each.value` = 이번 반복의 **맵 값** (맵 값이 객체면 `each.value.cidr` 처럼 중첩 접근 가능)

**리소스 주소 형태**: Terraform은 각 인스턴스를 키 기반으로 관리한다.

```
aws_subnet.public["ap-northeast-2a"]
aws_subnet.public["ap-northeast-2c"]
```

**for_each에 set(string)을 넣으면**: `each.key`와 `each.value`가 동일하다 (set은 값 자체가 키).

```hcl
for_each = toset(["a", "b", "c"])
# each.key == each.value == "a", "b", "c"
```

**for_each outputs — `values()` 필수**

for_each 리소스는 맵 형태로 관리되므로 ID 목록을 뽑으려면 `values()`로 먼저 리스트로 변환해야 한다.

```hcl
output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
  # values()로 맵 → 리스트 변환 후 [*].id 적용
}
```

---

### ⚠️ for_each key 변경 시 destroy/recreate 위험

```hcl
# 변경 전
for_each = { app = "10.0.0.0/16" }
# state: module.vpc["app"]

# 변경 후 — 이름만 바꿔도
for_each = { application = "10.0.0.0/16" }
# state: module.vpc["application"] ← 새 리소스로 인식
# → 기존 VPC destroy 후 재생성. 운영 중인 VPC가 삭제될 수 있음
```

**key는 변경되지 않을 안정적인 값으로 정해야 한다.**
- 좋은 key: `"ap-northeast-2a"`, `"public_a"`, `"app"` 같은 역할 기반 고정 식별자
- 나쁜 key: 인덱스 번호, 변경될 수 있는 이름

---

## 참고 문서
- Variables: https://developer.hashicorp.com/terraform/language/values/variables
- Outputs: https://developer.hashicorp.com/terraform/language/values/outputs
- Modules: https://developer.hashicorp.com/terraform/language/modules
- for_each: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- 검색 키워드: `terraform module input output`, `terraform for_each module`, `terraform module scope`
