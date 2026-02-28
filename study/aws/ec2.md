# EC2 (Elastic Compute Cloud)

> 마지막 업데이트: 2026-02-28

---

## 1. 개념 설명 (AWS 관점)

### EC2란?

EC2(Elastic Compute Cloud)는 AWS의 가상 서버 서비스다. 물리 서버를 구매하는 대신, AWS 데이터센터의 물리 호스트 위에 Hypervisor(Nitro System)가 올라가고, 그 위에 여러 개의 가상 머신(Instance)이 실행된다.

**왜 필요한가?**
- 물리 서버는 구매/배송/설치/교체에 수개월이 걸린다
- EC2는 API 한 번으로 수 초~수 분 내에 서버가 생긴다
- 트래픽에 따라 늘리고 줄일 수 있다 (Elastic)

### 내부 동작 방식

```
사용자 요청
    ↓
AWS Nitro Hypervisor (물리 호스트)
    ↓
EC2 Instance (Guest OS - Amazon Linux / Ubuntu 등)
    ├── ENI (Elastic Network Interface) → 네트워크 연결
    ├── EBS Volume → 루트 디스크
    └── Instance Store → 임시 고속 스토리지 (선택)
```

- **ENI**: 각 인스턴스는 반드시 하나 이상의 ENI를 가진다. ENI에 Private IP, Security Group이 붙는다
- **EBS**: 네트워크로 연결된 블록 스토리지. 인스턴스가 종료돼도 데이터 유지 가능
- **AMI(Amazon Machine Image)**: OS + 설정이 담긴 스냅샷. 인스턴스는 AMI를 기반으로 부팅된다

### 인스턴스 타입 선택 기준

| 패밀리 | 특징 | 용도 |
|--------|------|------|
| t4g, t3 | 버스트 가능, 저렴 | 개발, 소규모 웹 |
| m7i, m6i | 범용 균형 | 일반 앱 서버 |
| c7i, c6i | CPU 최적화 | 고연산 처리 |
| r7i, r6i | 메모리 최적화 | DB, 캐시 |

이 프로젝트에서는 App 서버이므로 `t3.micro`(개발) 또는 `m5.large`(운영) 정도가 적합하다.

### User Data

인스턴스 최초 부팅 시 실행되는 스크립트. 패키지 설치, 앱 배포 등에 사용한다.

```bash
#!/bin/bash
yum update -y
yum install -y nginx
systemctl enable nginx
systemctl start nginx
```

### Instance Profile (IAM Role)

EC2가 AWS 서비스(S3, SSM 등)에 접근할 때 자격증명을 하드코딩하면 안 된다. 대신 **IAM Role을 인스턴스에 붙인다(Instance Profile)**. 인스턴스는 내부 메타데이터 엔드포인트(`169.254.169.254`)에서 임시 자격증명을 자동으로 가져온다.

### 실무에서 자주 하는 실수

1. **Public IP 직접 할당** → ALB 뒤에 두면 필요 없다. Private Subnet에 두고 NAT로 아웃바운드만
2. **SSH Key Pair를 소스 관리에 커밋** → `.gitignore` 필수
3. **Security Group을 0.0.0.0/0으로 열기** → 최소 권한 원칙
4. **User Data 오류를 모르는 채로 넘어가기** → `/var/log/cloud-init-output.log` 확인
5. **IMDSv1 사용** → SSRF 취약점 위험. `http_tokens = "required"`로 IMDSv2 강제

---

## 2. Terraform 구현

### 필요한 리소스 목록

| 리소스 | 역할 |
|--------|------|
| `aws_instance` | EC2 인스턴스 본체 (단독 사용 시) |
| `aws_launch_template` | ASG와 함께 쓸 때 인스턴스 설정 템플릿 |
| `data.aws_ami` | 최신 AMI ID 자동 조회 |
| `aws_key_pair` | SSH 키 등록 |
| `aws_iam_role` | EC2에 붙일 IAM Role |
| `aws_iam_instance_profile` | Role을 EC2에 연결하는 래퍼 |
| `aws_iam_role_policy_attachment` | Role에 Policy 연결 |

> **이 프로젝트에서는 `aws_instance`를 직접 쓰지 않는다.**
> ASG(Auto Scaling Group)에서 관리하기 때문에 `aws_launch_template`을 사용한다.
> 하지만 EC2의 원리를 이해해야 Launch Template도 이해된다.

### aws_instance — 핵심 argument

```hcl
resource "aws_instance" "app" {
  # ① 어떤 이미지로 부팅할 것인가
  ami           = data.aws_ami.amazon_linux.id

  # ② 어떤 스펙의 서버인가
  instance_type = "t3.micro"

  # ③ 어느 서브넷(네트워크 위치)에 둘 것인가
  subnet_id     = aws_subnet.private_app_a.id

  # ④ 어떤 방화벽(Security Group)을 적용할 것인가
  vpc_security_group_ids = [aws_security_group.app.id]

  # ⑤ IAM Role 연결 (AWS 서비스 접근 권한)
  iam_instance_profile = aws_iam_instance_profile.app.name

  # ⑥ 최초 부팅 스크립트
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  # ⑦ IMDSv2 강제 (보안)
  metadata_options {
    http_tokens = "required"
  }

  # ⑧ 루트 볼륨 설정
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "app-server"
  }
}

# 최신 Amazon Linux 2023 AMI 자동 조회
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### IAM Instance Profile 구성

```hcl
# 1. EC2가 assume할 수 있는 Role 생성
resource "aws_iam_role" "app" {
  name = "app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 2. SSM 접속을 위한 Policy 연결 (SSH 대신)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3. Role → Instance Profile 변환 (EC2에 붙이려면 반드시 필요)
resource "aws_iam_instance_profile" "app" {
  name = "app-instance-profile"
  role = aws_iam_role.app.name
}
```

### Launch Template (실제 프로젝트에서 사용할 것)

```hcl
resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_tokens = "required"
  }

  # aws_launch_template의 user_data는 반드시 base64 인코딩
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
  EOF
  )

  # 새 버전이 생겨도 기존 ASG는 영향받지 않음 (명시적 업데이트 필요)
  lifecycle {
    create_before_destroy = true
  }
}
```

> **주의**: `aws_instance`의 `user_data`는 plain string이지만,
> `aws_launch_template`의 `user_data`는 **base64 인코딩**이 필요하다.

### 리소스 간 참조 관계

```
aws_vpc
  └── aws_subnet (subnet_id)
        └── aws_instance
              ├── aws_security_group (vpc_security_group_ids)
              ├── aws_iam_instance_profile (iam_instance_profile)
              │     └── aws_iam_role
              └── data.aws_ami (ami)
```

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 4 — Application Tier |
| 레이어 | `modules/compute/` |
| 구현 형태 | `aws_launch_template` (직접 `aws_instance` 아님) |

**선행 리소스 (먼저 있어야 함)**:
- VPC, Private App Subnet → Phase 1 (Network)
- Security Group (App SG) → Phase 2 (Security)
- IAM Role / Instance Profile → Phase 2 (Security)
- ALB Target Group → Phase 3 (Web Tier)

**후행 리소스 (이것이 있어야 가능)**:
- `aws_autoscaling_group` → Launch Template을 참조
- `aws_autoscaling_policy` → ASG를 참조
- CloudWatch Alarms → ASG 메트릭을 참조

---

## 4. 직접 해볼 것

**지금 해볼 실습**: `modules/compute/` 구조를 설계해보자.

```
modules/compute/
  ├── main.tf          # aws_launch_template, aws_autoscaling_group
  ├── variables.tf     # subnet_ids, sg_id, instance_type 등
  └── outputs.tf       # asg_name, launch_template_id
```

어떤 값을 `variables.tf`로 받아야 할지 생각해보는 것이 핵심이다.

**참고 문서**:
- [aws_launch_template | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template)
- [aws_instance | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
- 검색 키워드: `terraform ec2 launch template user_data base64`, `EC2 IMDSv2 terraform`
