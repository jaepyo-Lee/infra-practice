# Terraform tfvars 관리 패턴

마지막 업데이트: 2026-02-28

---

## 한 줄 요약

`variables.tf` = "어떤 변수를 받는지 선언", `terraform.tfvars` = "실제 값 주입"

---

## 1. 역할 분리

```
variables.tf      ← 변수 선언 (타입, 설명, 기본값 구조)
terraform.tfvars  ← 실제 값 주입 (환경마다 다른 값)
```

```hcl
# variables.tf
variable "name" {
  type        = string
  description = "환경 이름"
}

# terraform.tfvars
name = "dev"
```

`terraform plan/apply` 실행 시 같은 디렉토리의 `terraform.tfvars`를 자동으로 읽는다.

---

## 2. 값 주입 우선순위 (높을수록 나중에 덮어씀)

```
default 값 (variables.tf)
    ↓
terraform.tfvars
    ↓
*.auto.tfvars
    ↓
-var 플래그 (CLI 직접 전달)
```

같은 변수가 여러 곳에 있으면 우선순위가 높은 쪽이 이긴다.

---

## 3. 관리 패턴

### 패턴 1: `.tfvars.example`로 템플릿 공유 (권장)

민감한 값이 포함될 수 있을 때 사용한다.

```
terraform.tfvars         ← .gitignore 처리 (실제 값, 공유 X)
terraform.tfvars.example ← git 추적 (템플릿, 공유 O)
```

`terraform.tfvars.example` 내용:
```hcl
name        = "dev"
cidr        = "10.0.0.0/16"
db_password = ""   # Secrets Manager에서 주입 권장
```

팀원 온보딩 절차:
1. 저장소 clone
2. `cp terraform.tfvars.example terraform.tfvars`
3. 실제 값 채우기

### 패턴 2: 환경별 파일 분리

```
envs/dev/vpc/terraform.tfvars   ← dev 값
envs/prod/vpc/terraform.tfvars  ← prod 값
```

같은 `variables.tf` 구조를 공유하면서 값만 환경별로 다르게 관리한다.

---

## 4. .gitignore 설정

```gitignore
# 민감한 값이 포함될 수 있으므로 기본적으로 제외
*.tfvars
*.tfvars.json

# 템플릿 파일은 예외 처리
!terraform.tfvars.example
```

민감한 값이 없는 tfvars라도 git에 올리지 않는 것이 관례다.
나중에 민감한 값이 추가될 수 있고, 습관을 일관되게 유지하는 것이 중요하다.

---

## 5. 민감값 처리 원칙

`terraform.tfvars`에 패스워드, API Key를 절대 직접 쓰지 않는다.

| 민감값 종류 | 권장 방법 |
|------------|---------|
| DB 패스워드 | AWS Secrets Manager → `data "aws_secretsmanager_secret_version"` |
| API Key | AWS SSM Parameter Store → `data "aws_ssm_parameter"` |
| 임시 환경 | 환경변수 `TF_VAR_변수명=값 terraform apply` |

```bash
# 환경변수로 민감값 전달 예시
TF_VAR_db_password="my-secret" terraform apply
```

Terraform은 `TF_VAR_` 접두사가 붙은 환경변수를 자동으로 변수로 인식한다.

---

## 참고 문서

- [Input Variables](https://developer.hashicorp.com/terraform/language/values/variables)
- 검색 키워드: `terraform tfvars gitignore`, `terraform TF_VAR environment variable`, `terraform sensitive variable`
