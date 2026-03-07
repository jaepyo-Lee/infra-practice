# AWS Secrets Manager

> 마지막 업데이트: 2026-03-07

---

## 1. 개념 설명

### 왜 필요한가

App 서버가 RDS에 접속하려면 DB 비밀번호가 필요하다. 이 비밀번호를 어디에 보관할까?

- ❌ 코드에 하드코딩 → Git에 올라가는 순간 유출
- ❌ EC2 환경변수로 직접 주입 → AMI에 남거나 로그에 찍힐 수 있음
- ❌ S3에 파일로 저장 → 접근 제어가 까다롭고 감사 추적 어려움
- ✅ **Secrets Manager** → 암호화 저장, IAM으로 접근 제어, 자동 교체 지원

### 내부 동작 방식

```
EC2 (App Tier)
  ↓ IAM Role로 인증
Secrets Manager API 호출 (GetSecretValue)
  ↓ 복호화된 값 반환
앱이 DB 연결에 사용
```

EC2에 붙인 IAM Role에 `secretsmanager:GetSecretValue` 권한이 있어야 한다. **IAM과 항상 세트**다.

### 비밀값 저장 형태

Secrets Manager는 시크릿을 JSON 문자열로 저장한다.

```json
{
  "username": "admin",
  "password": "super-secret-pw",
  "host": "my-db.cluster-xyz.rds.amazonaws.com",
  "port": 3306
}
```

앱은 이 JSON을 파싱해서 각 필드를 DB 연결에 사용한다.

### 자동 교체 (Rotation)

Lambda를 트리거해 주기적으로 비밀번호를 자동 변경한다. RDS와 연동하면 앱 다운타임 없이 DB 비밀번호를 교체할 수 있다.

### Secrets Manager vs SSM Parameter Store

| | Secrets Manager | SSM Parameter Store |
|--|----------------|---------------------|
| 용도 | 민감한 시크릿 (DB 패스워드, API Key) | 설정값, 환경변수 |
| 자동 교체 | ✅ 지원 | ❌ 미지원 |
| 비용 | 시크릿당 월 $0.40 | 표준 파라미터 무료 |
| 암호화 | 기본으로 KMS 암호화 | SecureString 타입만 암호화 |

**DB 비밀번호처럼 교체가 필요하고 민감한 값** → Secrets Manager
**앱 설정값, 환경 구분 플래그** → Parameter Store

---

## 2. Terraform 핵심 파라미터

### `aws_secretsmanager_secret` — 껍데기(메타데이터)

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | ✅ | 시크릿 이름. `/`로 계층 구조 표현 가능 (`myapp/dev/db`) |
| `description` | 선택 | 설명 |
| `recovery_window_in_days` | 선택 | 삭제 후 복구 가능 기간 (기본 30일). `0`이면 즉시 삭제 |

**`recovery_window_in_days = 0`**: 실습 환경에서 중요하다. 기본값 30일이면 `terraform destroy` 후 같은 이름으로 재생성할 때 30일 동안 이름 충돌이 발생한다. 실습 환경에서는 반드시 `0`으로 설정한다.

**이름 규칙**: `{프로젝트}/{환경}/{용도}` 패턴 권장
```
myapp/dev/rds-credentials
myapp/prod/rds-credentials
```

### `aws_secretsmanager_secret_version` — 실제 값

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `secret_id` | ✅ | `aws_secretsmanager_secret`의 id |
| `secret_string` | ✅ | 저장할 값. JSON 문자열 권장 |

**주의**: `secret_string`에 민감한 값이 들어가므로 Terraform state에도 평문으로 저장된다. S3 Backend의 `encrypt = true`가 필수인 이유다.

---

## 3. 이 프로젝트에서의 위치

**Phase 2 — Security Layer** (`modules/security/`)

의존 관계:
```
[선행] IAM Role (secretsmanager:GetSecretValue 권한)
    → [현재] Secrets Manager (RDS 자격증명 저장)
    → [후행] RDS (비밀번호를 시크릿 ARN으로 참조)
```

구현할 리소스:
1. `aws_secretsmanager_secret` — RDS 자격증명용 껍데기
2. `aws_secretsmanager_secret_version` — username/password JSON 저장

RDS를 아직 만들지 않았으므로 지금은 더미 값으로 시크릿을 만들고, RDS 구현 후 실제 엔드포인트로 업데이트한다.

→ [핵심 블록 & for_each](../terraform/core-blocks.md)
→ [Backend & State 암호화](../terraform/backend.md)

---

## 4. 민감값 관리 패턴

Secrets Manager에 넣을 실제 값을 어떻게 관리하느냐에 따라 3가지 패턴이 있다.

### 패턴 1 — 껍데기만 Terraform, 값은 CLI 주입 (학습 환경 권장)

Terraform은 `aws_secretsmanager_secret`(메타데이터)만 생성하고, 실제 값은 별도로 주입한다.
`aws_secretsmanager_secret_version`을 Terraform으로 관리하지 않는다.

```bash
# Terraform apply 후 AWS CLI로 직접 주입
aws secretsmanager put-secret-value \
  --secret-id myapp/dev/db \
  --secret-string '{"password":"실제비밀번호"}'
```

- 장점: 코드/state에 민감값 없음, 가장 안전
- 단점: 수동 작업 필요, 자동화 어려움

### 패턴 2 — random_password 리소스로 자동 생성

```hcl
resource "random_password" "db" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}
```

- 장점: 완전 자동화
- 단점: **tfstate에 평문으로 저장됨** → S3 Backend `encrypt = true` 필수

### 패턴 3 — tfvars + .gitignore (소규모 팀)

```hcl
# variables.tf
variable "db_password" {
  type      = string
  sensitive = true  # plan/apply 출력에서 값을 가림
}
```

```bash
# terraform.tfvars (반드시 .gitignore에 추가)
db_password = "실제비밀번호"
```

- 장점: 단순
- 단점: tfvars 파일 관리 실수 시 Git에 노출 위험

---

## 5. CI/CD 환경변수 주입 패턴

GitHub Actions + GitHub Secrets를 이용해 코드 외부에서 값을 주입하는 방법.

```
GitHub Secrets → GitHub Actions → TF_VAR_* 환경변수 → Terraform
```

**GitHub Actions workflow 예시:**
```yaml
- name: Terraform Apply
  run: terraform apply -auto-approve
  env:
    TF_VAR_db_password: ${{ secrets.DB_PASSWORD }}
```

Terraform은 `TF_VAR_변수명` 환경변수를 자동으로 variable로 인식한다.

**환경별 실행 비교:**
```
로컬:  terraform apply → 직접 입력 또는 .tfvars (gitignore)
CI/CD: terraform apply → GitHub Secrets에서 TF_VAR_* 로 자동 주입
```

코드 어디에도 실제 값이 없고, 저장소(GitHub Secrets)만 다를 뿐이다.