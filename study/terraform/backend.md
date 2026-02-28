# Terraform Backend (backend.tf)

> 마지막 업데이트: 2026-02-28

---

## 1. 개념 설명 (왜 필요한가)

`backend.tf`는 **Terraform State 파일을 어디에 저장할지** 지정하는 설정 파일이다.

### State 파일이란?

`terraform apply`를 실행하면 Terraform은 "내가 어떤 리소스를 만들었는지"를 기록한 파일을 만든다. 이게 **State 파일** (`terraform.tfstate`)이다.

```
terraform apply 실행
    ↓
AWS에 리소스 생성 (EC2, VPC, RDS...)
    ↓
terraform.tfstate에 기록
    ↓
다음 apply 시 이 파일을 읽어 "현재 상태"와 "원하는 상태"를 비교
```

State 파일이 없으면 Terraform은 기존 리소스를 몰라서 **중복 생성하거나 삭제를 시도**한다.

### Backend가 필요한 이유

기본 설정(Local Backend)은 State를 **내 컴퓨터 로컬**에 저장한다.

| 문제 | 설명 |
|------|------|
| **팀 협업 불가** | A가 apply하면 A 컴퓨터에만 State가 있음. B는 모름 |
| **State 충돌** | A, B 동시에 apply하면 State가 꼬임 |
| **유실 위험** | 컴퓨터 날리면 State도 같이 사라짐 |
| **CI/CD 불가** | GitHub Actions 같은 파이프라인은 로컬 파일에 접근 불가 |

**Remote Backend**는 이 문제를 해결한다. State를 S3 같은 공용 저장소에 올리고, DynamoDB로 동시 접근을 잠근다.

---

## 2. 핵심 문법 및 패턴

### 기본 구조

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"   # State 저장할 S3 버킷
    key            = "dev/vpc/terraform.tfstate"   # 버킷 안의 경로
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock"              # State Lock용 DynamoDB 테이블
    encrypt        = true                          # S3 서버 측 암호화
  }
}
```

### key 경로 설계 — 환경 분리의 핵심

`key`는 S3 버킷 안에서의 경로다. 환경별로 다르게 설정해야 State가 섞이지 않는다.

```
# dev 환경
key = "dev/vpc/terraform.tfstate"
key = "dev/security/terraform.tfstate"

# prod 환경
key = "prod/vpc/terraform.tfstate"
key = "prod/security/terraform.tfstate"
```

같은 S3 버킷을 쓰더라도 `key` 경로가 다르면 State가 완전히 분리된다.

### DynamoDB State Lock

두 사람이 동시에 `apply`하면 State가 깨진다. DynamoDB가 이를 막는다.

```
A: terraform apply 시작
    → DynamoDB에 Lock 획득
    → apply 진행 중

B: terraform apply 시작
    → DynamoDB에 Lock 시도
    → "State is locked by A" 에러 → 대기 또는 중단

A: apply 완료 → Lock 해제
    → B가 Lock 획득 가능
```

DynamoDB 테이블에는 `LockID`라는 파티션 키가 반드시 있어야 한다.

#### Lock의 동작 메커니즘 — "점유/해제" 방식

Lock은 **지속적으로 업데이트되는 것이 아니라**, apply 동안만 레코드가 존재하고 끝나면 삭제된다.

```
apply 시작  → DynamoDB에 LockID 레코드 생성   (잠금)
apply 진행  → 레코드 그대로 유지              (점유 중)
apply 완료  → DynamoDB에서 LockID 레코드 삭제  (해제)
```

DynamoDB 테이블의 항목 수:

| 상태 | 항목 수 |
|------|--------|
| 아무도 apply 안 하는 중 | 0개 (비어있음) |
| 누군가 apply 중 | 1개 (LockID 레코드 존재) |
| apply 완료 후 | 다시 0개 |

State 파일 자체는 S3에 저장되고, DynamoDB는 오직 **"지금 누가 쓰고 있냐"** 만 관리한다.

#### Lock이 해제되지 않는 경우

apply 도중 강제 종료되면 Lock이 남아있을 수 있다. 이때는 수동으로 해제:

```bash
terraform force-unlock <LOCK_ID>
```

### backend는 변수를 쓸 수 없다

Terraform의 유명한 제약이다:

```hcl
# ❌ 이렇게 쓰면 에러
variable "env" { default = "dev" }

terraform {
  backend "s3" {
    key = "${var.env}/terraform.tfstate"  # 변수 사용 불가!
  }
}
```

backend 블록은 Terraform 초기화(`terraform init`) 시점에 평가되는데, 이때는 아직 변수를 읽지 않는다.

**해결책 — partial configuration:**

```bash
# backend.tf에는 버킷/리전/테이블만 (공통 값)
terraform {
  backend "s3" {
    bucket         = "my-state-bucket"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

# 환경별로 init할 때 key를 직접 전달
terraform init -backend-config="key=dev/vpc/terraform.tfstate"
```

---

## 3. 실전 활용

### 이 프로젝트에서의 위치

이 프로젝트는 `envs/dev/vpc/`, `envs/dev/security/` 처럼 레이어별로 디렉토리가 분리되어 있다. 각 디렉토리마다 `backend.tf`가 따로 필요하다.

```
envs/
  dev/
    vpc/
      backend.tf      ← key: "dev/vpc/terraform.tfstate"
      main.tf
    security/
      backend.tf      ← key: "dev/security/terraform.tfstate"
  prod/
    vpc/
      backend.tf      ← key: "prod/vpc/terraform.tfstate"
```

레이어를 분리하는 이유: `vpc`를 바꿀 때 `rds` State에 영향을 주지 않기 위해서다. State가 하나면 변경 범위가 너무 커진다.

### 관련 개념

| 개념 | 관계 |
|------|------|
| `terraform.tfstate` | backend가 관리하는 파일 |
| `terraform init` | backend 설정을 읽고 초기화하는 명령 |
| `data "terraform_remote_state"` | 다른 State의 output을 읽어오는 방법 |
| S3 버킷 Versioning | State 실수로 날렸을 때 복원 가능하게 해줌 |

---

## 4. 직접 해볼 것

현재 `envs/dev/vpc/`에 `backend.tf`가 있는지 확인하고, 없다면 만들어보자.

체크리스트:
- [ ] S3 버킷 이름이 전역 유일한가? (버킷 이름은 전 세계 유일해야 함)
- [ ] `key` 경로가 환경/레이어별로 다른가?
- [ ] DynamoDB 테이블에 `LockID` 파티션 키가 있는가?
- [ ] `encrypt = true`가 설정되어 있는가?

**참고 문서:**
- [Terraform Backend S3](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- 검색 키워드: `terraform backend s3 dynamodb lock`, `terraform partial configuration backend`