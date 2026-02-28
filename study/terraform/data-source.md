# Terraform Data Source (`data` 블록)

마지막 업데이트: 2026-02-28

---

## 한 줄 요약

`resource`는 AWS 리소스를 **만드는** 것, `data`는 이미 있는 것을 **읽어오는** 것.

---

## 1. 왜 필요한가

Terraform이 직접 만들지 않은 리소스(외부에 이미 존재하거나, 동적으로 바뀌는 값)를 참조해야 할 때 사용한다.

대표적인 문제:
- EC2 AMI ID는 리전마다 다르고 시간이 지나면 바뀜 → 하드코딩 불가
- AZ 목록은 리전마다 다름 → 하드코딩하면 다른 리전에서 동작 안 함
- 다른 Terraform 스택이 만든 VPC ID를 참조해야 함

```hcl
# ❌ 하드코딩 — 리전 변경 시 깨짐, 시간 지나면 구버전
resource "aws_instance" "app" {
  ami = "ami-0abcd1234"
}

# ✅ data로 동적으로 가져오기 — 항상 최신, 리전 독립적
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "app" {
  ami = data.aws_ami.amazon_linux.id
}
```

---

## 2. 문법

```hcl
# 선언
data "<타입>" "<이름>" {
  # 필터 조건
}

# 참조: data.<타입>.<이름>.<속성>
data.aws_ami.amazon_linux.id
```

`resource`와 참조 방법 비교:
```
resource "aws_vpc" "main"    → aws_vpc.main.id           (data. 없음)
data    "aws_vpc" "existing" → data.aws_vpc.existing.id  (data. 있음)
```

---

## 3. `resource` vs `data` 핵심 차이

| | `resource` | `data` |
|--|------------|--------|
| AWS 변경 여부 | 생성 / 수정 / 삭제 | 없음 (읽기 전용) |
| plan 결과 | `+`, `~`, `-` 표시 | 표시 안 됨 |
| 관리 주체 | Terraform이 생명주기 관리 | 외부에 이미 존재하는 리소스 |
| 오류 시점 | apply 시 | plan 시 (조회 실패하면 바로 에러) |

---

## 4. 이 프로젝트에서 자주 쓰는 패턴

### AZ 목록 동적으로 가져오기 (Subnet 구현 시 필수)

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

# 결과: ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
# 사용: for_each나 element()로 서브넷에 AZ 배정
```

하드코딩 없이 해당 리전의 사용 가능한 AZ를 자동으로 가져온다.

### 현재 AWS 계정 ID 가져오기

```hcl
data "aws_caller_identity" "current" {}

# 사용 예: IAM 정책 ARN 구성 시
# "arn:aws:s3:::${data.aws_caller_identity.current.account_id}-tfstate"
```

### 최신 AMI 가져오기

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### 다른 Terraform state에서 값 가져오기

스택이 VPC / App / DB 등으로 분리됐을 때, 다른 스택의 output을 참조하는 방법.

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-tfstate-bucket"
    key    = "dev/vpc/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

resource "aws_security_group" "app" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}
```

### Secrets Manager에서 민감값 가져오기

```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "dev/rds/password"
}

# 사용: jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]
```

---

## 5. 안티패턴

```hcl
# ❌ data source 결과를 변수 default에 사용 (불가 — 런타임 값이라 정적 평가 안 됨)
variable "ami_id" {
  default = data.aws_ami.amazon_linux.id  # 에러
}

# ✅ locals로 별칭 만들기
locals {
  ami_id = data.aws_ami.amazon_linux.id
}
```

---

## 6. 이 프로젝트에서의 위치

| Phase | 사용 위치 | data 타입 |
|-------|-----------|-----------|
| Phase 1 | modules/vpc — Subnet 생성 시 | `aws_availability_zones` |
| Phase 4 | modules/asg — AMI 선택 시 | `aws_ami` |
| Phase 5 | modules/rds — 비밀번호 주입 | `aws_secretsmanager_secret_version` |
| Phase 7 | 스택 분리 시 state 참조 | `terraform_remote_state` |

---

## 참고 문서

- Data Sources 개요: https://developer.hashicorp.com/terraform/language/data-sources
- aws_availability_zones: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
- aws_ami: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
- 검색 키워드: `terraform data source filter`, `terraform_remote_state`, `aws_availability_zones terraform`
