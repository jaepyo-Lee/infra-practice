# Terraform 핵심 블록: resource, variable, output, module

마지막 업데이트: 2026-03-07 (Phase 2 IAM 리소스 패턴 추가)

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
# iam.tf
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
# envs/dev/iam.tf
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

### ⚠️ for_each 리소스 참조 안티패턴 — `.id` 직접 참조 불가

`for_each`로 만든 리소스는 내부적으로 **맵(map)** 으로 관리된다. 단일 리소스처럼 `.id`를 직접 참조하면 에러가 발생한다.

```hcl
# ❌ 안티패턴: for_each 리소스를 단일 리소스처럼 참조
resource "aws_nat_gateway" "nat" {
  subnet_id = aws_subnet.public.id
  # 에러: aws_subnet.public은 맵이므로 .id 속성이 없다
}
```

**올바른 참조 방법 2가지:**

**1. for_each 블록 내부 — `each.value.id`**

```hcl
resource "aws_nat_gateway" "nat" {
  for_each  = aws_subnet.public
  subnet_id = each.value.id  # 현재 순회 중인 서브넷의 ID
}
```

**2. for_each 블록 외부 — `["키"].id`**

```hcl
# 특정 AZ의 서브넷 ID를 명시적으로 참조
subnet_id = aws_subnet.public["ap-northeast-2a"].id
```

**같은 키로 두 리소스를 1:1 연결하는 패턴:**

EIP와 NAT GW를 `aws_subnet.public`으로 동일하게 for_each하면, 같은 AZ 키로 서로를 참조할 수 있다.

```hcl
resource "aws_eip" "nat" {
  for_each = aws_subnet.public  # 키: "ap-northeast-2a", "ap-northeast-2c"
  domain   = "vpc"
}

resource "aws_nat_gateway" "nat" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id  # 같은 AZ 키로 EIP 참조
  subnet_id     = each.value.id
}
```

`each.key`가 동일한 맵을 순회하므로 AZ별 1:1 매핑이 자동으로 성립한다.

---

## 참고 문서
- Variables: https://developer.hashicorp.com/terraform/language/values/variables
- Outputs: https://developer.hashicorp.com/terraform/language/values/outputs
- Modules: https://developer.hashicorp.com/terraform/language/modules
- for_each: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- 검색 키워드: `terraform module input output`, `terraform for_each module`, `terraform module scope`

---

## `for` 표현식 — map 필터링 패턴

`for_each`와 함께 자주 쓰이는 패턴. map에서 조건에 맞는 항목만 걸러낼 때 사용한다.

### 기본 문법

```hcl
{ for k, v in 맵 : k => v if 조건 }
```

| 부분 | 의미 |
|------|------|
| `for k, v in 맵` | map 순회. `k`=키, `v`=값 |
| `: k => v` | 결과 map의 키-값 구성 |
| `if 조건` | true인 항목만 포함 |

### 예시 — is_global 플래그로 리소스 분기

```hcl
# 입력 map
var.acm = {
  "alb_cert" = { domain_name = "api.example.com", is_global = false }
  "cf_cert"  = { domain_name = "example.com",     is_global = true  }
}

# is_global = false만 필터링
{ for k, v in var.acm : k => v if !v.is_global }
# 결과: { "alb_cert" = { ... } }

# is_global = true만 필터링
{ for k, v in var.acm : k => v if v.is_global }
# 결과: { "cf_cert" = { ... } }
```

### 왜 쓰는가

Terraform의 `provider` 메타 인수는 동적으로 설정할 수 없다. 리소스를 두 개로 나누고 for 필터링으로 각각 다른 provider를 적용하는 패턴이다.

```hcl
# ALB용 (ap-northeast-2)
resource "aws_acm_certificate" "regional" {
  for_each = { for k, v in var.acm : k => v if !v.is_global }
  provider = aws.ap_northeast_2
  ...
}

# CloudFront용 (us-east-1)
resource "aws_acm_certificate" "global" {
  for_each = { for k, v in var.acm : k => v if v.is_global }
  provider = aws.us_east_1
  ...
}
```

### for 표현식 전체 패턴 정리

```hcl
# 리스트 → 리스트
[ for item in list : item.name ]

# 리스트 → map
{ for item in list : item.key => item }

# map → map (전체)
{ for k, v in map : k => v }

# map → map (필터링)
{ for k, v in map : k => v if 조건 }

# 중첩 map 평탄화 (flatten 대안)
[ for k, v in map : { key = k, value = v } ]
```

---

## 11. AWS 리소스별 핵심 파라미터 — Phase 1 Network

> 각 리소스를 Terraform으로 생성할 때 쓰는 인수(argument)의 의미와 필요성 설명.

---

### `aws_internet_gateway`

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `vpc_id` | ✅ | 이 IGW를 연결할 VPC | 에러 — IGW는 반드시 VPC에 attach |
| `tags` | 선택 | AWS 리소스 태그 | 태그 없음. Name 없으면 콘솔에서 식별 어려움 |

**핵심**: IGW는 파라미터가 거의 없다. `vpc_id`만 있으면 된다. 복잡한 건 Route Table에서 한다.

---

### `aws_route_table`

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "public-rt" }
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `vpc_id` | ✅ | 이 Route Table이 속할 VPC | 에러 |
| `route.cidr_block` | ✅ (route 블록 내) | 이 경로의 목적지 CIDR | 에러 |
| `route.gateway_id` | 선택 | 패킷을 보낼 IGW ID | 경로 없음 (대신 nat_gateway_id 등 사용) |
| `route.nat_gateway_id` | 선택 | 패킷을 보낼 NAT GW ID | Private 서브넷 아웃바운드 불가 |
| `tags` | 선택 | 태그 | - |

**`route` 블록**: 인라인으로 여러 경로를 선언할 수 있다. 단, 인라인 `route`와 별도 `aws_route` 리소스를 혼용하면 충돌 위험 — 한 가지 방식만 사용한다.

**`0.0.0.0/0`의 의미**: "나머지 모든 목적지". 더 구체적인 경로(`10.0.0.0/16 → local`)가 먼저 매칭되고, 아무것도 안 맞으면 이 경로로 폴백.

---

### `aws_route_table_association`

```hcl
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `subnet_id` | ✅ | 연결할 서브넷 ID | 에러 |
| `route_table_id` | ✅ | 연결할 Route Table ID | 에러 |

**왜 별도 리소스인가**: Route Table을 만든다고 서브넷에 자동으로 붙지 않는다. 명시적 연결이 없으면 서브넷은 VPC Default Route Table을 사용한다. Default RT에 실수로 IGW 경로를 추가하면 모든 서브넷이 Public이 되는 보안 사고 발생.

---

### `aws_eip`

```hcl
resource "aws_eip" "nat" {
  for_each = { for az, _ in var.public_subnets : az => az }
  domain   = "vpc"

  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "nat-eip-${each.key}" }
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `domain` | ✅ | `"vpc"` 고정 | 구 API 방식 deprecated. vpc 스코프 EIP로 명시 |
| `depends_on` | 권장 | IGW가 먼저 있어야 EIP가 라우팅 가능 | 간헐적 생성 실패 또는 라우팅 오류 |
| `tags` | 선택 | 태그 | - |

**`domain = "vpc"` 왜 필요한가**: AWS에는 과거 EC2-Classic(2006~2022, 모든 고객이 공유하는 플랫 네트워크)과 EC2-VPC(현재, 격리된 가상 네트워크) 두 플랫폼이 있었다. EIP도 플랫폼별로 별도 생성이 필요했고 `domain`이 그 구분자였다. EC2-Classic은 2022년 8월 완전 종료됐으므로 지금은 `"vpc"`만 유효하다. 생략하면 deprecated 경고 또는 에러 발생.

**EIP는 독립적으로 존재한다**: NAT GW를 삭제해도 EIP는 남는다. 연결 안 된 EIP는 비용이 발생하므로 NAT GW 삭제 시 EIP도 반드시 함께 삭제해야 한다.

---

### `aws_nat_gateway`

```hcl
resource "aws_nat_gateway" "main" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  connectivity_type = "public"

  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "nat-gw-${each.key}" }
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `allocation_id` | ✅ (public type) | NAT GW에 할당할 EIP ID | 에러. Public NAT GW는 고정 IP 필수 |
| `subnet_id` | ✅ | NAT GW를 배치할 서브넷 ID | 에러 |
| `connectivity_type` | 선택 | `"public"` (기본) 또는 `"private"` | 기본값 `"public"` 적용 |
| `depends_on` | 권장 | IGW가 먼저 있어야 인터넷 통신 가능 | 생성은 되지만 트래픽 흐름 불가 |
| `tags` | 선택 | 태그 | - |

**`subnet_id`는 Public Subnet을 가리켜야 한다**: NAT GW가 인터넷에 접근하려면 IGW로 향하는 Route가 있는 Public Subnet에 위치해야 한다. Private Subnet에 두면 인터넷과 통신 불가.

**`connectivity_type = "private"`**: VPC 간 통신(Transit Gateway 등)을 위한 Private NAT GW. EIP 불필요. 일반적인 학습 환경에서는 쓰지 않는다.

**`depends_on`이 필요한 이유**: Terraform은 `aws_eip`와 `aws_nat_gateway`가 독립적으로 생성 가능하다고 판단해 병렬로 실행할 수 있다. 하지만 IGW가 VPC에 attach되지 않은 상태에서 Public IP를 가진 NAT GW가 만들어지면 라우팅이 불안정하다. `depends_on`으로 IGW attach 완료 후 NAT GW를 생성하도록 순서를 명시한다.

---

## 12. AWS 리소스별 핵심 파라미터 — Phase 2 Security (IAM)

---

### `aws_iam_role`

IAM Role의 핵심은 두 가지 정책이다: **누가 이 Role을 쓸 수 있는가(Trust Policy)** 와 **이 Role로 무엇을 할 수 있는가(Permission Policy)** 다.

```hcl
resource "aws_iam_role" "app" {
  name = "app-ec2-role"

  # Trust Policy: "ec2.amazonaws.com이 이 Role을 assume할 수 있다"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "app-ec2-role" }
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `name` | ✅ | Role 이름. AWS 계정 내 유일해야 함 | 에러 |
| `assume_role_policy` | ✅ | Trust Policy JSON 문자열. 누가 이 Role을 assume할 수 있는지 정의 | 에러 |
| `tags` | 선택 | 태그 | - |

**`assume_role_policy`는 `jsonencode()` 또는 `data "aws_iam_policy_document"` 로 작성한다.**

`jsonencode()` 방식:
```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = { Service = "ec2.amazonaws.com" }
    Action    = "sts:AssumeRole"
  }]
})
```

`data "aws_iam_policy_document"` 방식 (권장):
```hcl
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "app-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
```

**`Principal`의 형태**: EC2 외 다른 서비스를 허용할 때 `Service` 값을 바꾼다.
- EC2: `"ec2.amazonaws.com"`
- Lambda: `"lambda.amazonaws.com"`
- ECS Task: `"ecs-tasks.amazonaws.com"`

---

### `aws_iam_policy`

```hcl
data "aws_iam_policy_document" "app_permissions" {
  # statement 1: Secrets Manager 읽기
  statement {
    sid     = "SecretsManagerRead"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = ["*"]  # 실무에서는 ARN으로 범위 좁히기
  }

  # statement 2: CloudWatch 로그 쓰기
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app" {
  name        = "app-ec2-policy"
  description = "App EC2 인스턴스용 권한"
  policy      = data.aws_iam_policy_document.app_permissions.json
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `name` | ✅ | Policy 이름. AWS 계정 내 유일해야 함 | 에러 |
| `policy` | ✅ | Permission Policy JSON 문자열 | 에러 |
| `description` | 선택 | Policy 설명. 나중에 콘솔에서 식별용 | - |

**`sid` (Statement ID)**: 각 statement에 붙이는 이름. 선택사항이지만 달아두면 어떤 권한인지 바로 알 수 있다.

---

### `aws_iam_role_policy_attachment`

Role과 Policy를 연결하는 리소스. Role을 만들고, Policy를 만들고, 이 리소스로 둘을 연결한다.

```hcl
resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `role` | ✅ | Role 이름 (name 속성, ARN이 아님) | 에러 |
| `policy_arn` | ✅ | Policy ARN | 에러 |

**AWS Managed Policy를 붙일 때**: ARN을 직접 작성한다.
```hcl
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

**같은 Role에 Policy 여러 개**: `aws_iam_role_policy_attachment` 블록을 여러 개 만들면 된다.
```hcl
resource "aws_iam_role_policy_attachment" "custom" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

---

### `aws_iam_instance_profile`

EC2에 Role을 붙이기 위한 래퍼. EC2는 Role을 직접 참조하지 못하고 Instance Profile을 통해 참조한다.

```hcl
resource "aws_iam_instance_profile" "app" {
  name = "app-ec2-instance-profile"
  role = aws_iam_role.app.name
}
```

| 파라미터 | 필수 | 의미 | 없으면? |
|---------|------|------|---------|
| `name` | ✅ | Instance Profile 이름 | 에러 |
| `role` | ✅ | 연결할 IAM Role 이름 | 에러 |

**EC2 Launch Template에서의 참조**:
```hcl
resource "aws_launch_template" "app" {
  # ...
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
}
```

---

### 전체 흐름 요약

```
[data] aws_iam_policy_document "assume_role"
    ↓ .json
[resource] aws_iam_role "app"          (Trust Policy: EC2가 assume 가능)
    ↓ .name
[resource] aws_iam_role_policy_attachment  (Role ↔ Policy 연결)
    ↑ .arn
[resource] aws_iam_policy "app"        (Permission: Secrets Manager 읽기 등)
    ↑ data.aws_iam_policy_document "app_permissions" .json

[resource] aws_iam_instance_profile "app"
    → aws_iam_role.app.name
    → Launch Template의 iam_instance_profile.name 으로 참조
```

**생성 순서** (Terraform이 자동으로 결정):
1. `aws_iam_role` + `aws_iam_policy` (병렬 생성)
2. `aws_iam_role_policy_attachment` (둘 다 완료 후)
3. `aws_iam_instance_profile` (role 완료 후)

---

### 실수하기 쉬운 것

**1. `role`에 ARN 대신 name을 써야 한다**
```hcl
# ❌ ARN을 넣으면 에러
role = aws_iam_role.app.arn

# ✅ name을 넣어야 함
role = aws_iam_role.app.name
```

**2. `data "aws_iam_policy_document"` 는 리소스를 생성하지 않는다**

`apply`해도 AWS에 아무것도 만들지 않는다. 단순히 JSON 문자열을 계산하는 데이터 소스다. `.json` 속성으로 결과를 꺼내 쓴다.

**3. Permission Policy와 Trust Policy를 혼동**

| | 어디에 쓰는가 | 무엇을 정의하는가 |
|--|-------------|----------------|
| Trust Policy | `aws_iam_role.assume_role_policy` | 누가 이 Role을 assume할 수 있는가 |
| Permission Policy | `aws_iam_policy.policy` | 이 Role로 무엇을 할 수 있는가 |

Trust Policy 없이 Role만 만들면 아무도 그 Role을 쓸 수 없다. Permission Policy 없이 Role만 assume할 수 있어도 실제로 할 수 있는 것이 없다.
