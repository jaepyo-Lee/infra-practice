# ECS (Elastic Container Service)

> 마지막 업데이트: 2026-03-07 (Capacity Provider, ECS Auto Scaling, ECS Exec, CI/CD lifecycle 패턴 추가)

---

## 1. 개념 설명

### ECS란?

AWS가 완전 관리하는 **컨테이너 오케스트레이터**다. Docker 컨테이너를 어디에서 몇 개 실행할지, 장애 시 어떻게 재시작할지를 자동으로 관리한다.

EC2 기반 아키텍처와 비교:

```
EC2 기반 (ASG)                    ECS 기반
─────────────────                 ─────────────────
서버(VM)를 직접 관리               컨테이너 단위로 관리
AMI + User Data로 앱 배포          Docker Image로 앱 배포
인스턴스 교체 = 새 VM 부팅          컨테이너 교체 = 이미지 Pull + 재시작
스케일: 인스턴스 단위               스케일: Task 단위 (더 빠름)
```

---

### 핵심 구성 개념 4가지

```
ECR (이미지 저장소)
  └── Docker Image 보관

ECS Cluster (실행 환경)
  └── Task가 실제로 실행되는 공간 (논리적 그룹)

Task Definition (설계도)
  └── 컨테이너 이미지, CPU/메모리, 환경변수, 포트 정의
  └── "이 컨테이너를 이렇게 실행해라"는 명세서

Service (운영 관리자)
  └── Task를 몇 개 유지할지 관리
  └── 장애 시 자동 재시작
  └── ALB와 연결해 트래픽 분산
```

---

### Fargate vs EC2 Launch Type

ECS는 컨테이너가 **어디서 실행되는지**에 따라 두 가지 모드가 있다.

| 항목 | Fargate | EC2 Launch Type |
|------|---------|----------------|
| 서버 관리 | AWS가 전담 (Serverless) | 직접 EC2 인스턴스 관리 |
| 비용 구조 | vCPU + 메모리 사용량 과금 | EC2 인스턴스 시간 과금 |
| 밀집도 제어 | 불가 (AWS가 결정) | 가능 (인스턴스당 Task 수 조정) |
| 스팟 활용 | Fargate Spot 가능 | EC2 Spot 가능 |
| 적합한 상황 | 소규모, 운영 부담 최소화 | 대규모, 비용 최적화 필요 |

학습 목적 + 소규모라면 **Fargate가 훨씬 간단하다.** EC2를 별도로 띄우지 않아도 된다.

---

### ECS와 ASG(EC2)의 선택 기준

| 상황 | 추천 |
|------|------|
| 앱이 이미 컨테이너화 되어 있음 | ECS |
| 배포 주기가 짧고 롤링 업데이트 필요 | ECS |
| 앱이 컨테이너화가 어려운 레거시 | EC2 ASG |
| GPU 작업, 특수 인스턴스 타입 필요 | EC2 ASG |
| 운영 인력이 없고 단순하게 시작 | ECS Fargate |

**실무 트렌드**: 신규 서비스는 ECS(Fargate) → 트래픽/비용이 커지면 EC2 Launch Type 또는 EKS로 전환하는 경로가 일반적이다.

---

### ALB와의 연동 구조

```
인터넷
  ↓
ALB
  ↓ (Target Group — IP mode)
ECS Service
  ├── Task 1 (Container: 10.0.11.5:8080)
  ├── Task 2 (Container: 10.0.11.6:8080)
  └── Task 3 (Container: 10.0.12.7:8080)
```

EC2 ASG는 Target Group이 인스턴스 ID를 등록하지만, ECS Fargate는 **컨테이너 IP**를 직접 등록한다(IP mode). 컨테이너가 교체될 때 ALB Target Group도 자동 갱신된다.

---

### ECR — 이미지 저장소

Docker Hub 대신 AWS 내부 프라이빗 레지스트리다.

```
로컬 빌드:  docker build -t my-app .
ECR Push:   docker push 123456.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest
ECS Pull:   Task Definition이 이 URI를 참조해 이미지를 받아 실행
```

VPC 내부에서 ECR 접근 시 인터넷을 경유하지 않으려면 **VPC Endpoint (ECR용)** 를 설정해야 한다.
없으면 NAT Gateway를 통해 ECR에 접근 → NAT 데이터 비용 발생.

---

### IAM 역할 구분 — Task Role vs Execution Role

ECS에서는 IAM Role이 두 개 필요하다. 혼동하기 쉬운 부분이다.

| Role | 사용 주체 | 용도 |
|------|---------|------|
| **Task Execution Role** | ECS 에이전트(AWS) | ECR에서 이미지 Pull, CloudWatch에 로그 전송 |
| **Task Role** | 컨테이너 안의 앱 | S3 읽기, Secrets Manager 접근, DynamoDB 쿼리 등 |

```
ECS 에이전트 (AWS 인프라 측)
  └── Task Execution Role 사용
  └── "ECR에서 이미지 내려받을게요, CloudWatch에 로그 보낼게요"

컨테이너 내부 앱 (내 코드)
  └── Task Role 사용
  └── "S3에서 파일 읽을게요, RDS 연결 정보를 Secrets Manager에서 가져올게요"
```

Task Role이 없으면 앱에서 AWS SDK로 S3, Secrets Manager 등에 접근할 때 권한 오류가 난다.

---

### 실무에서 자주 하는 실수

1. **Task Definition CPU/메모리 너무 작게** → OOM으로 컨테이너 계속 재시작
2. **Task Role 누락** → 컨테이너가 S3, Secrets Manager 접근 불가
3. **ALB Target Group을 Instance mode로** → Fargate는 반드시 IP mode 사용
4. **ECR VPC Endpoint 없이 Fargate 사용** → NAT 비용 과다 발생
5. **컨테이너 로그 설정 누락** → CloudWatch Logs 연결 안 하면 장애 원인 파악 불가

---

---

## 1-B. 실무 심화 패턴 (실무 코드 분석)

### Capacity Provider — Fargate + EC2 혼합 전략

Capacity Provider는 ECS Task를 어디서 실행할지 결정하는 전략이다.
실무에서는 FARGATE / FARGATE_SPOT / EC2를 혼합해 비용과 안정성을 균형있게 맞춘다.

```
FARGATE      → 안정적, 비쌈 (On-Demand)
FARGATE_SPOT → 저렴하지만 중단 가능 (중단 허용 가능한 batch 작업에 적합)
EC2          → 서버 직접 관리, 가장 저렴 (대용량 트래픽 시)
```

**Cluster에서 Capacity Provider 등록:**
```hcl
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT", aws_ecs_capacity_provider.ec2.name]

  # 기본 전략: Prod는 안정성 우선 FARGATE
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}
```

**Service에서 Capacity Provider 선택:**
```hcl
resource "aws_ecs_service" "this" {
  capacity_provider_strategy {
    capacity_provider = "FARGATE"  # 이 서비스는 FARGATE 고정
    weight            = 1
    base              = 1
  }
}
```

**EC2 Capacity Provider 구성 (ECS-managed Auto Scaling):**

EC2 인스턴스를 ASG로 관리하면서 ECS가 직접 스케일링하는 방식.

```
ECS Task 요청 증가
    ↓
ECS Capacity Provider가 ASG에게 "인스턴스 더 줘"
    ↓
ASG가 EC2 인스턴스 추가
    ↓
ECS Task 배치
```

```hcl
resource "aws_ecs_capacity_provider" "ec2" {
  name = "my-ec2-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_ec2.arn
    managed_termination_protection = "ENABLED"  # ECS Task 실행 중 인스턴스 종료 방지

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100  # 인스턴스 용량의 100%까지 사용
      maximum_scaling_step_size = 2    # 한 번에 최대 2개 추가
      minimum_scaling_step_size = 1    # 한 번에 최소 1개 추가
    }
  }
}
```

**mixed_instances_policy — r6i.large로 실제 운영:**

Launch Template에 기본 인스턴스 타입을 지정하고, ASG에서 다른 타입으로 override하는 패턴.

```hcl
resource "aws_autoscaling_group" "ecs_ec2" {
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_ec2.id
        version            = "$Latest"
      }

      # Launch Template의 t3.medium을 r6i.large로 override
      override {
        instance_type = "r6i.large"
      }
    }

    instances_distribution {
      on_demand_percentage_above_base_capacity = 100  # 100% On-Demand (Spot 없음)
    }
  }

  protect_from_scale_in = true  # Capacity Provider의 managed termination protection과 함께 사용
}
```

**EC2 User Data — ECS 클러스터 등록:**
```bash
#!/bin/bash
# 이 EC2가 어느 ECS 클러스터에 속하는지 알려줌
echo "ECS_CLUSTER=my-cluster-name" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
```

---

### ECS Application Auto Scaling

ECS Service의 Task 수를 CPU/메모리 기준으로 자동으로 조정한다.

```
aws_appautoscaling_target   → "이 ECS 서비스의 Task 수를 1~6개 범위에서 조정"
aws_appautoscaling_policy   → "CPU 40% 넘으면 늘려라"
```

```hcl
resource "aws_appautoscaling_target" "this" {
  max_capacity       = 6
  min_capacity       = 2
  resource_id        = "service/my-cluster/my-service"  # ECS 서비스 경로
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 40           # CPU 40% 목표
    scale_in_cooldown  = 300          # 축소는 5분 쿨다운 (플래핑 방지)
    scale_out_cooldown = 60           # 확장은 1분 쿨다운 (빠르게 대응)
  }
}
```

**Scale Out vs Scale In Cooldown 설계 원칙:**
- Scale Out (확장): 빠르게 (60초) — 트래픽 급증에 즉각 대응
- Scale In (축소): 느리게 (300초) — 트래픽이 잠깐 줄었다가 다시 오르면 불필요한 축소/확장 반복(플래핑) 발생

**Prod 환경의 Auto Scaling 설정 (실무 기준):**
```hcl
min_capacity              = 2     # HA: 최소 2개 (AZ 분산)
max_capacity              = 6
autoscaling_cpu_target    = 40    # CPU 40% 목표 (여유 확보)
autoscaling_memory_target = 80    # Memory 80% 목표
scale_out_cooldown        = 60    # 확장은 빠르게
scale_in_cooldown         = 300   # 축소는 천천히 (5분)
```

---

### ECS Exec — 컨테이너에 직접 접속 (SSM)

Fargate 컨테이너에는 SSH가 없다. ECS Exec는 SSM Session Manager를 통해 컨테이너 안에 쉘로 직접 접속하는 기능이다.

```
개발자 로컬
    ↓
AWS SSM Session Manager (인터넷)
    ↓
ECS Task (Private Subnet) ← VPC Endpoint 필요
    ↓
컨테이너 쉘 (bash)
```

**Terraform 설정:**
```hcl
resource "aws_ecs_service" "this" {
  enable_execute_command = true  # ECS Exec 활성화
}
```

**Task Role에 SSM 권한 필요:**
```hcl
resource "aws_iam_role_policy" "ecs_exec" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}
```

**실제 접속 명령 (AWS CLI):**
```bash
aws ecs execute-command \
  --cluster my-cluster \
  --task task-id \
  --container container-name \
  --command "/bin/bash" \
  --interactive
```

**VPC Endpoint 필요:** Private Subnet에서 인터넷 없이 SSM을 사용하려면 SSM Interface Endpoint 3개 필요.
- `com.amazonaws.{region}.ssm`
- `com.amazonaws.{region}.ssmmessages`
- `com.amazonaws.{region}.ec2messages`

---

### CI/CD와 Terraform의 역할 분리

실무에서 ECS는 Terraform과 CI/CD(GitHub Actions 등)가 **동시에 관리**한다. 이 역할 분리를 이해하지 못하면 Terraform apply가 배포 내용을 덮어쓰는 문제가 생긴다.

```
Terraform이 관리:              CI/CD가 관리:
─────────────────              ─────────────────
Task Definition 기본 뼈대      새 Docker 이미지 → 새 Task Definition revision
ECS Service 설정               Service를 새 revision으로 업데이트
IAM Role, Security Group       desired_count (Auto Scaling)
ALB, Target Group              container_definitions 실제 이미지 태그
```

**해결책: `ignore_changes`로 역할 명확히 분리**
```hcl
resource "aws_ecs_task_definition" "this" {
  lifecycle {
    ignore_changes = [container_definitions]  # CI/CD가 관리
  }
}

resource "aws_ecs_service" "this" {
  lifecycle {
    ignore_changes = [
      desired_count,       # Auto Scaling이 관리
      task_definition,     # CI/CD가 관리 (새 revision으로 업데이트)
    ]
  }
}
```

---

### Deployment Circuit Breaker — 배포 실패 자동 롤백

새 버전 배포 시 Health Check가 계속 실패하면 자동으로 이전 버전으로 롤백한다.

```hcl
resource "aws_ecs_service" "this" {
  deployment_maximum_percent         = 200   # 배포 중 최대 200% Task 실행 허용
  deployment_minimum_healthy_percent = 100   # 배포 중 최소 100% 정상 유지

  deployment_circuit_breaker {
    enable   = true   # Circuit Breaker 활성화
    rollback = true   # 실패 시 자동 롤백
  }
}
```

**동작 흐름:**
```
새 Task Definition으로 배포 시작
    ↓
새 컨테이너가 Health Check 실패 반복
    ↓
Circuit Breaker 발동
    ↓
이전 Task Definition revision으로 자동 롤백
    ↓
서비스 정상 유지
```

**주의:** Circuit Breaker는 배포 자체 실패를 잡아내지만, 배포 후 운영 중 발생하는 장애는 잡지 못한다.

---

### GitHub OIDC — 비밀 키 없이 GitHub Actions에서 AWS 접근

GitHub Actions에서 AWS에 접근할 때 Access Key를 저장하지 않고, OIDC 토큰으로 AssumeRole하는 방식.

```
GitHub Actions 실행
    ↓
GitHub이 JWT 토큰 발급 (OIDC)
    ↓
AWS IAM이 토큰 검증 (OIDC Provider)
    ↓
임시 자격 증명(AssumeRole) 반환
    ↓
ECR Push, ECS 배포
```

**Terraform 설정 (Global 레벨):**
```hcl
# OIDC Provider 생성 (계정당 한 번)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# GitHub Actions용 IAM Role
resource "aws_iam_role" "github_actions" {
  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:my-org/my-repo:*"
        }
      }
    }]
  })
}
```

**최소 권한 원칙:** 서비스별로 ECR/ECS 권한을 분리해서 부여한다.
- frontend용 ECR: `arn:aws:ecr:region:account:repository/project-prod-frontend`
- backend용 ECR: `arn:aws:ecr:region:account:repository/project-prod-backend`
- scheduler용 ECR: `arn:aws:ecr:region:account:repository/project-prod-scheduler-*` (wildcard)

---

## 2. Terraform 구현 참고

→ [핵심 블록 & for_each 패턴](../terraform/core-blocks.md)
→ [모듈 구조 컨벤션](../terraform/module-structure.md)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 4 — Application Tier |
| 레이어 | `modules/ecs/` (또는 `modules/asg/`와 선택) |

**선행 리소스**:
- `aws_vpc`, `aws_subnet` (private_nat) — Task가 실행될 네트워크
- `aws_lb_target_group` — ALB와 연결 (IP mode)
- `aws_ecr_repository` — 이미지 저장소
- `aws_iam_role` (Task Role + Execution Role)

**후행 리소스**:
- 없음. App Tier가 DB Tier에 접근하므로 DB가 먼저 있어야 실제 동작하지만, 리소스 생성 순서상 ECS Service는 독립적으로 생성 가능

---

## 4. 직접 해볼 것

Task Definition 설계도를 먼저 JSON으로 작성해보자 (Terraform 전에).

- 컨테이너 이름, 이미지 URI, 포트 매핑 정의
- CPU: 256 (.25 vCPU), Memory: 512 (0.5 GB) — Fargate 최솟값
- `logConfiguration`으로 CloudWatch Logs 연결

**AWS 공식 문서**:
- [ECS Fargate 시작하기](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/getting-started-fargate.html)
- 검색 키워드: `ecs fargate task definition terraform`, `ecs service alb integration ip mode`, `ecr vpc endpoint terraform`
