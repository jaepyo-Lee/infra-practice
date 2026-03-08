# Auto Scaling Group (ASG) & Launch Template

> 마지막 업데이트: 2026-03-08

---

## 1. 개념 설명 (AWS 관점)

### Launch Template이란?

EC2 인스턴스를 찍어낼 **청사진(템플릿)**이다. AMI, 인스턴스 타입, Security Group, IAM Role, User Data 등을 미리 정의해두고, ASG가 이를 참조해 인스턴스를 자동 생성한다.

`aws_instance`와의 차이:
- `aws_instance` → 인스턴스 1개를 직접 생성, 수동 관리
- `aws_launch_template` → 청사진만 정의, ASG가 N개를 자동 생성

### Auto Scaling Group이란?

Launch Template을 기반으로 EC2 인스턴스를 **자동으로 늘리고 줄이는** 서비스다.

**내부 동작 흐름:**

```
CloudWatch 메트릭 수집 (CPU, 커스텀 메트릭 등)
    ↓
Scaling Policy 조건 판단
    ↓
ASG가 Launch Template으로 인스턴스 생성/종료
    ↓
새 인스턴스 → ALB Target Group에 자동 등록
    ↓
헬스체크 통과 → 트래픽 수신 시작
```

### 이 프로젝트에서의 역할

```
인터넷 → CloudFront → ALB → [ASG 관리 EC2 인스턴스들] → RDS
                                      ↑
                              Phase 4 구현 영역
                              (Private App Subnet)
```

- Multi-AZ 배포: `vpc_zone_identifier`에 AZ-a, AZ-b private subnet 모두 지정
- ALB와 연결: `target_group_arns`로 자동 등록/해제
- 부팅 완료 전 트래픽 차단: `health_check_grace_period`로 대기

---

## 2. Terraform 핵심 파라미터

### `aws_launch_template`

| 파라미터 | 의미 | 필수 | 주의사항 |
|----------|------|------|----------|
| `image_id` | 부팅 AMI ID | 필수 | `data.aws_ami`로 최신 버전 자동 참조 권장 |
| `instance_type` | 인스턴스 타입 (t3.micro 등) | 필수 | dev/prod 분리 |
| `vpc_security_group_ids` | 붙일 SG 목록 | 필수 | app_sg만, ALB SG 아님 |
| `iam_instance_profile.name` | Instance Profile 이름 | 선택 | ARN이 아니라 name |
| `user_data` | 부팅 스크립트 | 선택 | **base64encode() 필수** |
| `metadata_options.http_tokens` | IMDSv2 강제 | 선택 | `"required"` 권장 (보안) |
| `update_default_version` | 버전 업데이트 시 기본값 자동 갱신 | 선택 | `true` 설정 시 ASG가 새 버전 자동 참조 |

**User Data 주의사항:**
```hcl
user_data = base64encode(<<-EOF
  #!/bin/bash
  yum update -y
  # ...
  EOF
)
```
`base64encode()`를 빠뜨리면 인스턴스 부팅 시 User Data가 실행되지 않는다.

**IMDSv2 강제 (보안 필수):**
```hcl
metadata_options {
  http_tokens                 = "required"   # IMDSv2 강제
  http_put_response_hop_limit = 1            # 컨테이너 환경이면 2
}
```
IMDSv1은 SSRF 공격으로 IAM 자격증명 탈취 가능. IMDSv2는 토큰 기반으로 방어.

---

### `aws_autoscaling_group`

| 파라미터 | 의미 | 필수 | 주의사항 |
|----------|------|------|----------|
| `min_size` | 최소 인스턴스 수 | 필수 | 0이면 트래픽 처리 불가 |
| `max_size` | 최대 인스턴스 수 | 필수 | 비용 상한선 역할 |
| `desired_capacity` | 현재 유지할 수량 | 선택 | min~max 사이 |
| `vpc_zone_identifier` | 인스턴스를 띄울 Subnet ID 목록 | 필수 | private subnet, Multi-AZ |
| `target_group_arns` | ALB Target Group ARN | 선택 | 없으면 ALB가 트래픽 전달 안 함 |
| `health_check_type` | `"EC2"` 또는 `"ELB"` | 선택 | **ELB 권장**: 앱 헬스체크 실패 시 교체 |
| `health_check_grace_period` | 부팅 후 헬스체크 대기 시간(초) | 선택 | 너무 짧으면 정상 인스턴스 교체됨 |

**`health_check_type` 차이:**
- `"EC2"`: EC2 인스턴스 상태만 체크 (하드웨어/OS 장애)
- `"ELB"`: ALB 헬스체크 결과를 사용 (앱이 응답 안 하면 교체)
- 실무에서는 `"ELB"` 사용이 표준. 앱이 죽었는데 EC2는 살아있는 경우 처리 가능.

**Launch Template 연결 방법:**
```hcl
launch_template {
  id      = aws_launch_template.app.id
  version = aws_launch_template.app.latest_version
  # 또는 version = "$Latest"
}
```

---

### `aws_autoscaling_policy` (Target Tracking)

```hcl
resource "aws_autoscaling_policy" "cpu" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0  # CPU 60% 유지
  }
}
```

- `policy_type = "TargetTrackingScaling"`: 목표치를 유지하도록 자동 조정 (권장)
- `SimpleScaling`: 조건 충족 시 N개 추가/제거 (쿨다운 필요, 구식)
- `StepScaling`: 메트릭 크기에 따라 단계적으로 조정

---

## 3. Data Source: 최신 AMI 자동 참조

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

`image_id = data.aws_ami.al2023.id`로 참조하면 AMI ID를 하드코딩하지 않아도 된다.

---

## 4. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 4 — Application Tier |
| 모듈 | `modules/app/` |
| 환경 레이어 | `envs/dev/app/` |
| Remote State Key | `dev/app/terraform.tfstate` |

**선행 리소스 (먼저 apply되어 있어야 함):**

```
Phase 1 (network)  → vpc_id, private_app_subnet_ids
Phase 2 (security) → sg_ids["app_sg"], iam_instance_profile_arns["app_role"]
Phase 3 (web)      → target_group_arn (ALB TG)
```

**후행 리소스 (Phase 4 이후):**
- Phase 5 (database): RDS 연결 정보를 User Data 또는 Secrets Manager로 주입
- Phase 6 (monitoring): ASG 메트릭을 CloudWatch에서 수집

---

## 5. 폴더 구조

```
modules/app/
├── main.tf          # aws_launch_template, aws_autoscaling_group, data.aws_ami
├── scaling.tf       # aws_autoscaling_policy
├── variables.tf     # subnet_ids, sg_id, instance_profile_name, target_group_arn 등
└── outputs.tf       # asg_name, launch_template_id

envs/dev/app/
├── backend.tf       # S3 remote state (key: dev/app/terraform.tfstate)
├── data.tf          # network, security, web remote state 참조
├── main.tf          # module "app" { source = "../../../modules/app" }
├── variables.tf     # name, tags, instance_type 등
└── outputs.tf       # asg_name 등
```

---

## 6. 자주 하는 실수

1. **`user_data`에 `base64encode()` 빠뜨림** → 스크립트 실행 안 됨
2. **`health_check_type = "EC2"` 그대로 사용** → 앱 장애 시 자동 교체 안 됨
3. **`health_check_grace_period`가 너무 짧음** → 부팅 중 인스턴스를 unhealthy로 판단해 계속 교체
4. **Public Subnet에 ASG 배치** → Private Subnet이 맞음. ALB가 앞에 있으므로 EC2는 외부 노출 불필요
5. **`desired_capacity`를 Terraform으로 관리** → Scaling 후 apply하면 원래 값으로 롤백됨. `ignore_changes = [desired_capacity]` 설정 권장

```hcl
lifecycle {
  ignore_changes = [desired_capacity]
}
```

---

## 7. 직접 해볼 것

`modules/app/variables.tf`에서 받을 변수 목록을 먼저 설계해보자:
- 어떤 값이 네트워크 레이어에서 오는지
- 어떤 값이 보안 레이어에서 오는지
- 어떤 값이 웹 레이어에서 오는지
- 어떤 값을 직접 `envs/dev/app/variables.tf`에서 정의할지

**참고 문서:**
- [aws_launch_template | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template)
- [aws_autoscaling_group | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group)
- [aws_autoscaling_policy | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy)
- 검색 키워드: `terraform launch template user_data base64`, `ASG target tracking scaling policy`, `EC2 IMDSv2 terraform`