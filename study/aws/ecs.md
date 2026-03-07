# ECS (Elastic Container Service)

> 마지막 업데이트: 2026-03-02

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
