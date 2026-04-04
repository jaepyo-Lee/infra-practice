# Terraform State 관리 실무
> 마지막 업데이트: 2026-04-04

> state가 꼬이는 건 실무에서 가장 흔한 사고 중 하나다.
> `terraform state` 명령어와 `moved` 블록을 제대로 알면 복구가 두렵지 않다.

---

## 1. State란 무엇인가

Terraform은 실제 인프라와 코드 사이의 **매핑 정보**를 `terraform.tfstate`에 저장한다.

```
코드 (main.tf)  ←→  state (.tfstate)  ←→  실제 AWS 리소스
```

- state가 없으면 Terraform은 어떤 리소스가 자기 것인지 모른다
- state가 코드와 어긋나면 `plan`이 엉뚱한 결과를 낸다
- state가 실제 리소스와 어긋나면 `apply`가 예상치 못한 삭제/재생성을 한다

---

## 2. 실무에서 state가 꼬이는 상황들

### 케이스 1: 리소스를 콘솔에서 직접 수정/삭제
```
실제 리소스: 변경됨
State:       이전 상태 그대로
코드:        이전 상태 그대로
→ plan에서 "drift" 발생
```

### 케이스 2: 리소스 이름(주소) 변경
```hcl
# 변경 전
resource "aws_instance" "web" { ... }

# 변경 후 (이름만 바꿨는데...)
resource "aws_instance" "web_server" { ... }
```
→ Terraform은 `web`을 삭제하고 `web_server`를 새로 만들려 한다 (실제론 같은 리소스인데!)

### 케이스 3: 모듈로 리팩토링
```hcl
# 변경 전: 루트에 직접 선언
resource "aws_vpc" "main" { ... }

# 변경 후: 모듈로 이동
module "network" {
  source = "./modules/network"
}
# 내부에 resource "aws_vpc" "main"
```
→ `aws_vpc.main` → `module.network.aws_vpc.main` 주소가 바뀜
→ 기존 VPC 삭제 후 새 VPC 생성 시도 (재앙)

### 케이스 4: count/for_each 전환
```hcl
# 변경 전: 단일 리소스
resource "aws_subnet" "public" { ... }

# 변경 후: for_each
resource "aws_subnet" "public" {
  for_each = var.azs
}
```
→ `aws_subnet.public` → `aws_subnet.public["ap-northeast-2a"]` 주소 변경

---

## 3. moved 블록 (Terraform 1.1+)

`moved` 블록은 "이 리소스는 저 주소로 이동했어"를 **코드로 선언**하는 방법이다.
state 파일을 직접 건드리지 않고, plan/apply 과정에서 자동으로 처리된다.

### 기본 문법
```hcl
moved {
  from = <이전 주소>
  to   = <새 주소>
}
```

### 예시 1: 리소스 이름 변경
```hcl
# main.tf
resource "aws_instance" "web_server" {
  # ...
}

moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

```bash
terraform plan
# 출력:
# aws_instance.web has moved to aws_instance.web_server
# No changes. Your infrastructure matches the configuration.
```

### 예시 2: 모듈로 리팩토링
```hcl
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}
```

### 예시 3: count → for_each 전환
```hcl
# 인덱스 0번을 특정 키로 매핑
moved {
  from = aws_subnet.public[0]
  to   = aws_subnet.public["ap-northeast-2a"]
}

moved {
  from = aws_subnet.public[1]
  to   = aws_subnet.public["ap-northeast-2c"]
}
```

### 예시 4: 모듈 이름 변경
```hcl
moved {
  from = module.vpc
  to   = module.network
}
```

### moved 블록의 장점
- Git에 이력이 남는다 (왜 이동했는지 추적 가능)
- 팀원 모두가 `terraform apply`만 하면 자동 처리
- 실수로 리소스를 삭제/재생성하는 사고 방지
- 모듈 제공자가 사용자의 기존 state를 망가뜨리지 않고 내부 구조 변경 가능

### moved 블록 정리 시점
moved 블록은 **영구적으로 둘 필요 없다.** 모든 사용자가 해당 버전 이후로 업그레이드했다면 삭제해도 된다. 하지만 지우기 전에 팀 전원이 apply했는지 확인할 것.

---

## 4. terraform state 명령어

`moved` 블록이 없던 시절, 또는 긴급 상황에서 직접 state를 조작하는 방법이다.

### 4-1. state 조회

```bash
# 현재 state에 어떤 리소스가 있는지 목록 확인
terraform state list

# 특정 리소스의 상세 정보 확인
terraform state show aws_instance.web

# 출력 예시:
# resource "aws_instance" "web" {
#   ami           = "ami-0c9c942bd7bf113a2"
#   instance_type = "t3.micro"
#   id            = "i-0a1b2c3d4e5f"
#   ...
# }
```

### 4-2. state mv (리소스 주소 변경)

`moved` 블록의 명령어 버전. 즉각적으로 state 파일을 수정한다.

```bash
# 기본 문법
terraform state mv <이전 주소> <새 주소>

# 예시: 리소스 이름 변경
terraform state mv aws_instance.web aws_instance.web_server

# 예시: 모듈로 이동
terraform state mv aws_vpc.main module.network.aws_vpc.main

# 예시: count → for_each
terraform state mv 'aws_subnet.public[0]' 'aws_subnet.public["ap-northeast-2a"]'
```

> **주의:** `state mv`는 즉시 state 파일을 변경한다. 반드시 백업 먼저!

### 4-3. state rm (state에서 리소스 제거)

리소스를 **실제로 삭제하지 않고** Terraform 관리에서만 제외한다.

```bash
# state에서 제거 (실제 AWS 리소스는 유지)
terraform state rm aws_instance.legacy_server

# 모듈 전체 제거
terraform state rm module.old_module
```

**언제 쓰나?**
- 콘솔에서 이미 수동 삭제한 리소스를 state에서 정리할 때
- 특정 리소스를 Terraform 관리에서 제외하고 싶을 때
- `terraform destroy` 없이 state만 깔끔하게 정리할 때

### 4-4. state pull / push (state 파일 직접 편집)

```bash
# 현재 state를 로컬로 가져오기
terraform state pull > backup.tfstate

# 수동으로 편집한 state를 업로드
terraform state push modified.tfstate
```

> **극도로 위험.** JSON을 직접 편집하면 형식 오류로 state가 완전히 망가질 수 있다.
> `state push`는 최후의 수단이다.

### 4-5. state replace-provider

provider 주소가 바뀔 때 사용. (예: 서드파티 provider → 공식 provider 전환)

```bash
terraform state replace-provider \
  registry.terraform.io/hashicorp/aws \
  registry.terraform.io/hashicorp/aws
```

---

## 5. import (기존 리소스를 Terraform 관리 하에 두기)

콘솔에서 만들어진 리소스를 코드로 가져오는 방법이다.

### 방법 1: import 블록 (Terraform 1.5+, 권장)

```hcl
# main.tf
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  # ...
}

import {
  to = aws_vpc.main
  id = "vpc-0a1b2c3d4e5f"  # 실제 AWS 리소스 ID
}
```

```bash
terraform plan   # import 미리 확인
terraform apply  # state에 등록
```

### 방법 2: CLI import (구방식)

```bash
# terraform import <리소스 주소> <AWS 리소스 ID>
terraform import aws_vpc.main vpc-0a1b2c3d4e5f
terraform import aws_instance.web i-0a1b2c3d4e5f
terraform import aws_s3_bucket.assets my-bucket-name
```

### generated config (Terraform 1.5+)

코드를 아직 안 썼어도 import 블록에 `id`만 넣으면 코드 초안을 자동 생성해준다.

```bash
terraform plan -generate-config-out=generated.tf
```

---

## 6. refresh (실제 인프라와 state 동기화)

콘솔에서 리소스를 변경했을 때 state를 현실에 맞게 업데이트한다.

```bash
# state를 실제 인프라 상태로 갱신
terraform apply -refresh-only

# 확인만 (state 변경 없음)
terraform plan -refresh-only
```

> `terraform refresh`는 deprecated. `-refresh-only` 플래그를 사용할 것.

---

## 7. 실무 체크리스트

### 리소스 이름/구조 변경 전
```bash
# 1. state 백업
terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate

# 2. 현재 state 목록 확인
terraform state list

# 3. moved 블록 작성 또는 state mv 실행

# 4. plan으로 반드시 확인
terraform plan
# → "No changes" 또는 "X moved"만 나와야 정상
# → destroy가 있으면 중단!
```

### 긴급 복구 순서
1. **plan 먼저** — 실제로 어떤 변화가 생기는지 확인
2. **백업** — `terraform state pull > backup.tfstate`
3. **state mv/rm** 으로 수정
4. **plan 재확인** — destroy 없는지 검증
5. **apply**

### moved vs state mv 선택 기준

| 상황 | 권장 방법 |
|------|-----------|
| 계획적인 리팩토링 | `moved` 블록 |
| 팀 협업, 코드 리뷰 필요 | `moved` 블록 |
| 긴급 복구, 즉시 처리 | `terraform state mv` |
| 이미 apply된 후 실수 수정 | `terraform state mv` |
| 외부에서 관리되는 모듈 업그레이드 | `moved` 블록 (모듈 내부) |

---

## 8. 자주 하는 실수와 해결법

### 실수 1: 리소스 rename 후 그냥 apply
```bash
# plan 결과에 이런 게 보이면 절대 apply 하지 말 것
# - aws_instance.web will be destroyed
# + aws_instance.web_server will be created

# 해결: moved 블록 추가 또는 state mv
```

### 실수 2: Remote backend에서 state lock 걸림
```bash
# 에러: Error acquiring the state lock
# 이전 apply가 비정상 종료되면 DynamoDB에 lock이 남는다

# 해결: lock ID 확인 후 강제 해제
terraform force-unlock <LOCK_ID>
# LOCK_ID는 에러 메시지에 포함되어 있음
```

### 실수 3: 여러 환경에서 같은 state 사용
```bash
# dev에서 terraform apply 했는데 prod state가 바뀜
# → workspace 또는 별도 backend 경로 사용

# workspace 활용
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
```

### 실수 4: count를 줄였는데 엉뚱한 리소스가 삭제됨
```hcl
# count 기반 리소스는 인덱스 순서로 삭제됨
# count = 3이었다가 count = 2로 줄이면 [2]가 삭제됨
# 중간 요소를 삭제하면 뒤의 것들이 재생성됨

# 해결: count 대신 for_each 사용 + moved 블록으로 마이그레이션
```

---

## 9. 실전 시나리오: 모듈 리팩토링

```
Before:
├── main.tf  (aws_vpc, aws_subnet, aws_igw 직접 선언)

After:
├── main.tf  (module "network" 호출)
└── modules/network/
    └── main.tf  (aws_vpc, aws_subnet, aws_igw)
```

### 안전한 마이그레이션 절차

```bash
# Step 1: 현재 state 확인
terraform state list
# aws_vpc.main
# aws_subnet.public[0]
# aws_subnet.public[1]
# aws_internet_gateway.main

# Step 2: 모듈 코드 작성 (아직 apply 하지 말 것)

# Step 3: moved 블록 추가
```

```hcl
# moves.tf
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_subnet.public[0]
  to   = module.network.aws_subnet.public["ap-northeast-2a"]
}

moved {
  from = aws_subnet.public[1]
  to   = module.network.aws_subnet.public["ap-northeast-2c"]
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}
```

```bash
# Step 4: plan으로 확인
terraform plan
# 기대 결과:
# Terraform will perform the following actions:
#   # aws_vpc.main has moved to module.network.aws_vpc.main
#   # aws_subnet.public[0] has moved to module.network.aws_subnet.public["ap-northeast-2a"]
#   ...
# Plan: 0 to add, 0 to change, 0 to destroy.

# Step 5: apply
terraform apply

# Step 6: 나중에 moves.tf 정리 (팀 전원 apply 완료 후)
```

---

## 관련 파일
- `study/terraform/backend.md` — Remote Backend 설정
- `study/terraform/lifecycle-and-import.md` — lifecycle, import 상세
- `study/terraform/module-structure.md` — 모듈 구조
