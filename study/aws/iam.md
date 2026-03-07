# IAM (Identity and Access Management)

> 마지막 업데이트: 2026-03-07

---

## 1. 개념 설명

### IAM이란

IAM은 AWS에서 **"누가 무엇을 할 수 있는가"** 를 제어하는 서비스다.

SG/NACL이 네트워크 레벨 접근 제어라면, IAM은 **API 레벨** 접근 제어다.
- SG: "이 IP/포트에서 오는 패킷을 허용할까?"
- IAM: "이 주체(EC2, Lambda, 사람)가 이 AWS API를 호출할 수 있을까?"

### 핵심 구성 요소

```
Principal (주체)
    ↓ assume (역할 위임)
Role (역할)
    ↓ attach
Policy (정책, JSON 문서)
    ↓ 정의
Effect + Action + Resource
```

- **Principal**: 누구? → IAM User, Group, Role, AWS 서비스(EC2, Lambda 등)
- **Policy**: 무엇을 허용/거부? → JSON으로 정의된 권한 문서
- **Role**: 역할. 사람이 아닌 **AWS 서비스가 다른 서비스를 호출할 때** 사용

### Policy 기본 구조

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

- `Effect`: Allow 또는 Deny
- `Action`: 허용/거부할 API 이름 (e.g. `secretsmanager:GetSecretValue`)
- `Resource`: 대상 리소스 ARN (`*`이면 전체)

### 왜 Role이 필요한가

App 서버(EC2)가 Secrets Manager에서 DB 비밀번호를 읽어야 할 경우:

- ❌ 잘못된 방법: EC2에 Access Key / Secret Key를 직접 저장 → 키 유출 시 전체 권한 탈취
- ✅ 올바른 방법: EC2에 **IAM Role** 부착 → AWS STS가 임시 자격증명을 자동 발급·갱신

Role은 두 가지 정책으로 구성된다:
- **Trust Policy (신뢰 정책)**: "누가 이 Role을 assume할 수 있는가?" → `sts:AssumeRole` 허용 대상
- **Permission Policy (권한 정책)**: "이 Role로 무엇을 할 수 있는가?" → 실제 AWS API 권한

```
Trust Policy:      "ec2.amazonaws.com이 이 Role을 assume할 수 있다"
Permission Policy: "Secrets Manager 읽기, CloudWatch 로그 쓰기 허용"
```

### Instance Profile이란

EC2에 Role을 직접 붙일 수 없다. Role을 감싸는 **Instance Profile** 이라는 래퍼가 필요하다.

```
EC2 → Instance Profile → IAM Role → Permission Policy
```

Terraform에서 `aws_iam_instance_profile` 리소스가 이 역할을 한다.
Launch Template에서 `iam_instance_profile { name = ... }` 으로 참조한다.

---

## 2. Terraform 핵심 파라미터

### `aws_iam_role`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | 필수 | Role 이름 |
| `assume_role_policy` | 필수 | Trust Policy JSON. "누가 이 Role을 assume할 수 있는가" |
| `description` | 선택 | Role 설명 |

`assume_role_policy`는 JSON 문자열이어야 한다. `jsonencode()` 또는 `data "aws_iam_policy_document"` 로 작성한다.

```hcl
# jsonencode() 방식
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = { Service = "ec2.amazonaws.com" }
    Action    = "sts:AssumeRole"
  }]
})
```

### `aws_iam_policy`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | 필수 | Policy 이름 |
| `policy` | 필수 | Permission Policy JSON |
| `description` | 선택 | Policy 설명 |

### `aws_iam_role_policy_attachment`

Role에 Policy를 연결하는 리소스.

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `role` | 필수 | 연결할 Role 이름 |
| `policy_arn` | 필수 | Policy ARN |

AWS Managed Policy를 붙일 때도 ARN을 직접 쓴다:
```
arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

### `aws_iam_instance_profile`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | 필수 | Instance Profile 이름 |
| `role` | 필수 | 연결할 Role 이름 |

---

## 3. 주의사항 및 자주 하는 실수

### 최소 권한 원칙 (Least Privilege)
`"Action": "*"` 처럼 모든 권한을 주면 안 된다. 필요한 API만 명시적으로 허용해야 한다.

### AWS Managed Policy vs Customer Managed Policy
- **AWS Managed**: AWS가 관리. 편리하지만 필요 이상의 권한 포함 가능
- **Customer Managed**: 직접 정의. 더 세밀하게 제어 가능. 실무에서 권장

### Resource ARN 범위
```
# 너무 넓음 (비권장)
"Resource": "*"

# 적절한 범위
"Resource": "arn:aws:secretsmanager:ap-northeast-2:123456789:secret:myapp/db/*"
```

### data aws_iam_policy_document
HCL 방식으로 Policy를 작성할 수 있어서 가독성이 좋고 오타 방지에 유리하다:
```hcl
data "aws_iam_policy_document" "app_policy" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}
```

---

## 4. 이 프로젝트에서의 위치

**Phase 2 — Security Layer** (`envs/dev/security/`, `modules/security/`)

의존 관계:
```
[선행] Network 모듈 (VPC) → [현재] IAM Role/Policy/Instance Profile → [후행] EC2 Launch Template (App Tier)
```

구현할 리소스:
1. `aws_iam_role` — App EC2용, trust policy: `ec2.amazonaws.com`
2. `aws_iam_policy` — Secrets Manager 읽기 + CloudWatch 로그 쓰기 권한
3. `aws_iam_role_policy_attachment` — Role ↔ Policy 연결
4. `aws_iam_instance_profile` — EC2에 붙이기 위한 래퍼

→ [핵심 블록 & for_each](../terraform/core-blocks.md)
→ [모듈 구조 컨벤션](../terraform/module-structure.md)