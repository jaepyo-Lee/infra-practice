# Terraform Lifecycle & Import

> 마지막 업데이트: 2026-03-07 (ignore_changes 섹션 추가)

---

## 1. 개념 설명 (왜 필요한가)

### State Drift — 핵심 문제

Terraform이 알고 있는 세계(State)와 AWS 실제 세계가 어긋나는 현상.

```
원인 1: AWS 콘솔에서 직접 리소스 삭제
         → Terraform State에는 여전히 존재
         → 다음 plan: "리소스가 사라짐, 재생성할게"

원인 2: State 파일 삭제 또는 손상
         → Terraform이 기존 리소스를 모름
         → 다음 apply: "없는 줄 알고" 재생성 시도
         → AWS: "이미 있는데?" → Conflict 에러 (InvalidSubnet.Conflict)

원인 3 (흔한 오해): terraform init -migrate-state 후 "기존 State"를 삭제
         → migrate-state는 State를 "이동"이 아니라 "복사"한다
         → 원본(이전 backend)이 자동 삭제되지 않는다
         → 새 backend의 State를 실수로 삭제하면 Terraform이 기억을 잃음

원인 3: count → for_each 전환 시 State 주소 변경
         → 기존: aws_subnet.public[0]
         → 신규: aws_subnet.public["ap-northeast-2a"]
         → Terraform: 이름이 다르므로 기존 것 삭제 + 새 것 생성
         → 실제로는 같은 리소스인데 불필요한 재생성 발생
```

---

## 2. 핵심 도구들

### `lifecycle { ignore_changes = [...] }`

특정 속성의 변경을 Terraform이 감지하지 않도록 무시한다.
Terraform은 기본적으로 `.tf` 코드와 실제 AWS 상태를 비교해 다르면 수정하는데, `ignore_changes`는 **특정 속성은 비교하지 말고 내버려둬** 라고 지시한다.

```hcl
resource "aws_secretsmanager_secret_version" "example" {
  secret_id     = aws_secretsmanager_secret.example.id
  secret_string = "초기값"  # 최초 apply 시에만 적용됨

  lifecycle {
    ignore_changes = [secret_string]
    # 이후 콘솔에서 값을 바꿔도 terraform plan에서 감지하지 않음
  }
}
```

**동작 흐름:**
```
최초 apply  → secret_string = "초기값" 으로 생성
콘솔에서    → secret_string = "실제비밀번호" 로 수동 변경
다음 plan   → secret_string 차이 감지 안 함 → No changes
```

**주요 사용 사례:**

| 상황 | 이유 |
|------|------|
| Secrets Manager 값 | 콘솔에서 수동 관리, Terraform이 덮어쓰지 않게 |
| EC2 AMI ID | 외부에서 AMI 업데이트해도 EC2 재생성 방지 |
| ASG desired_capacity | 오토스케일링이 조정한 값을 Terraform이 되돌리지 않게 |
| 외부 도구가 붙인 태그 | 다른 팀/도구가 추가한 태그를 Terraform이 지우지 않게 |

**`ignore_changes = all`**: 리소스의 모든 변경을 무시. 사실상 Terraform이 관리하지 않는 것과 같으므로 극히 드물게 쓴다.

**주의**: `ignore_changes`는 최초 생성 후에만 적용된다. 처음 `apply`에서는 정상적으로 값이 들어간다.

---

### `lifecycle { prevent_destroy = true }`

리소스를 실수로 삭제하는 것을 코드 레벨에서 막는다.
`terraform plan`에 destroy가 포함되면 에러를 내고 아예 실행을 막는다.

```hcl
resource "aws_subnet" "public" {
  for_each   = var.public_subnet_cidrs
  vpc_id     = aws_vpc.vpc.id
  cidr_block = each.value

  lifecycle {
    prevent_destroy = true
    # terraform destroy 또는 plan에 destroy가 포함되면 에러
    # 운영 환경의 DB, 서브넷, VPC 같은 핵심 리소스에 설정
  }
}
```

**언제 붙여야 하는가:**
- 서브넷, VPC — 삭제 시 그 안의 모든 리소스에 영향
- RDS, DB 클러스터 — 데이터 손실
- S3 버킷 (중요 데이터 보관) — 복구 불가

**제거하려면:**
`prevent_destroy = false`로 바꾸거나 `lifecycle` 블록 삭제 후 다시 apply.

---

### `terraform import`

AWS에 이미 존재하는 리소스를 Terraform State에 등록한다.
리소스를 건드리지 않고 "내가 이제 이것을 관리한다"고 선언하는 것.

```bash
# 기본 문법
terraform import <terraform-resource-address> <aws-resource-id>

# for_each 사용 시 (따옴표와 대괄호 주의)
terraform import 'module.main.aws_subnet.public["ap-northeast-2a"]' subnet-0a1b2c3d4e5f

# count 사용 시
terraform import 'aws_subnet.public[0]' subnet-0a1b2c3d4e5f
```

**import 후 워크플로우:**
```
terraform import ...
    ↓
terraform plan   # "No changes" 또는 태그 같은 소소한 차이만 나와야 정상
    ↓
terraform apply  # 차이 있으면 맞춤
```

**주의:** import는 State에만 등록할 뿐, `.tf` 코드를 자동으로 생성하지 않는다.
코드가 이미 있어야 한다.

---

### `terraform state mv`

State 파일 안의 리소스 주소(이름)를 변경한다.
AWS 리소스는 그대로 두고 State의 참조명만 바꾼다.

**가장 중요한 사용 사례: count → for_each 전환**

```bash
# count 방식으로 만든 서브넷을 for_each 방식 State로 이동
terraform state mv \
  'module.main.aws_subnet.public[0]' \
  'module.main.aws_subnet.public["ap-northeast-2a"]'

terraform state mv \
  'module.main.aws_subnet.public[1]' \
  'module.main.aws_subnet.public["ap-northeast-2c"]'

# 이렇게 하면:
# - AWS 서브넷은 삭제/재생성 없음
# - 서비스 중단 없음
# - State의 주소만 변경됨
```

**state mv 후 plan이 "No changes"여야 성공이다.**

---

### `terraform plan -out` 패턴

apply 전에 plan을 파일로 저장하고, 검토 후 그 plan만 실행한다.
plan과 apply 사이에 상태가 바뀌어도 동일한 변경만 적용된다.

```bash
terraform plan -out=tfplan     # plan 결과를 파일로 저장
terraform show tfplan          # 내용 확인 (destroy 포함 여부 주의)
terraform apply tfplan         # 저장된 plan 그대로 실행
```

destroy가 포함된 plan이면 "왜 삭제하려고 하는가?"를 반드시 파악 후 진행한다.

---

## 3. State Drift 복구 방법

### 상황별 대응표

| 상황 | 해결 방법 |
|------|---------|
| AWS에 있는데 State에 없음 | `terraform import` |
| State에 있는데 AWS에 없음 | `terraform state rm` → 다음 apply에서 재생성 |
| count → for_each 전환 | `terraform state mv` |
| State 전체 손상 | 백업에서 복원 (S3 Versioning) |

### 절대 하면 안 되는 것

```
❌ Terraform으로 만든 리소스를 AWS 콘솔에서 직접 삭제
   → State와 AWS 불일치 → 다음 apply에서 오류 또는 중복 생성 시도

❌ terraform.tfstate 파일을 수동으로 편집
   → 구조 깨지면 복구 불가

❌ State drift 상태에서 terraform apply 바로 실행
   → 항상 plan 먼저 확인
```

---

## 4. 이 프로젝트에서의 적용

### 오늘 발생한 에러의 원인

```
count 기반 서브넷을 for_each로 변경
    ↓
Terraform: 기존 aws_subnet.public[0] 삭제 + aws_subnet.public["ap-northeast-2a"] 생성
    ↓
삭제가 완료되기 전에 apply가 실패하거나
State만 삭제되고 AWS 리소스는 남은 경우
    ↓
다음 apply: "없는 줄 알고" 같은 CIDR로 생성 시도
    ↓
InvalidSubnet.Conflict: The CIDR '10.0.1.0/24' conflicts with another subnet
```

### 올바른 count → for_each 전환 방법

```bash
# 1. 코드 변경 전에 현재 State 확인
terraform state list

# 2. 코드를 for_each 방식으로 수정

# 3. apply 전에 state mv로 주소 변경
terraform state mv 'aws_subnet.public[0]' 'aws_subnet.public["ap-northeast-2a"]'
terraform state mv 'aws_subnet.public[1]' 'aws_subnet.public["ap-northeast-2c"]'

# 4. plan으로 destroy 없는지 확인
terraform plan  # No changes 또는 태그 차이만 있어야 함

# 5. apply
terraform apply
```

---

## 5. 직접 해볼 것

현재 에러 상황 복구 실습:

```bash
# AWS 콘솔에서 서브넷 ID 확인 후:
terraform state list  # 현재 State 확인

# 방법 A: 실습 환경이라면 콘솔에서 서브넷 삭제 후 apply
# 방법 B: import로 기존 서브넷을 State에 등록
terraform import 'module.main.aws_subnet.public["ap-northeast-2a"]' subnet-xxxxxxxx
```

**참고 문서:**
- [terraform import](https://developer.hashicorp.com/terraform/cli/import)
- [terraform state mv](https://developer.hashicorp.com/terraform/cli/state/mv)
- [lifecycle prevent_destroy](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- 검색 키워드: `terraform state drift`, `terraform import existing resource`, `count to for_each migration`
