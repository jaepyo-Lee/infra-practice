# Terraform Practice — AWS 3-Tier Architecture

> 실제 운영 가능한 AWS 클라우드 환경을 Terraform으로 구현하는 학습 프로젝트

---

## 목표

AWS 클라우드 아키텍처 역량을 갖춘 엔지니어가 되기 위해, **Production-Ready 3-Tier 아키텍처**를 Terraform으로 직접 구현한다.
단순히 리소스를 생성하는 것에 그치지 않고, 고가용성(HA), 보안, 비용 효율, 운영 관찰성까지 고려한 실전 수준의 인프라를 완성하는 것이 최종 목표다.

---

## 최종 아키텍처

```
                          ┌─────────────────────────────────────────┐
                          │               Internet                   │
                          └──────────────────┬──────────────────────┘
                                             │
                                    ┌────────▼────────┐
                                    │   Route 53      │  DNS
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │   CloudFront    │  CDN + HTTPS
                                    │     + WAF       │  DDoS 방어
                                    └────────┬────────┘
                                             │
┌────────────────────────────────────────────▼──────────────────────────────────────────────┐
│  VPC  (10.0.0.0/16)                                                                        │
│                                                                                            │
│  ┌──────────────────── Public Subnet ────────────────────┐                                │
│  │  AZ-a (10.0.1.0/24)          AZ-b (10.0.2.0/24)      │                                │
│  │  ┌─────────────┐             ┌─────────────┐          │  ← Internet Gateway            │
│  │  │  NAT GW     │             │  NAT GW     │          │                                │
│  │  └─────────────┘             └─────────────┘          │                                │
│  │  ┌──────────────────── ALB ────────────────────────┐  │                                │
│  │  │         Application Load Balancer               │  │                                │
│  │  └──────────────────────┬──────────────────────────┘  │                                │
│  └─────────────────────────│──────────────────────────────┘                               │
│                             │                                                              │
│  ┌──────────────────── Private Subnet (App) ──────────────┐                               │
│  │  AZ-a (10.0.11.0/24)         AZ-b (10.0.12.0/24)      │                               │
│  │  ┌─────────────────────────────────────────────────┐   │                               │
│  │  │          Auto Scaling Group                     │   │                               │
│  │  │   ┌──────────────┐   ┌──────────────┐          │   │                               │
│  │  │   │   EC2  (App) │   │   EC2  (App) │          │   │                               │
│  │  │   └──────────────┘   └──────────────┘          │   │                               │
│  │  └─────────────────────────────────────────────────┘   │                               │
│  └────────────────────────────────────────────────────────┘                               │
│                             │                                                              │
│  ┌──────────────────── Private Subnet (DB) ───────────────┐                               │
│  │  AZ-a (10.0.21.0/24)         AZ-b (10.0.22.0/24)      │                               │
│  │  ┌───────────────────────┐   ┌───────────────────────┐ │                               │
│  │  │  RDS Aurora (Primary) │   │  RDS Aurora (Replica) │ │                               │
│  │  └───────────────────────┘   └───────────────────────┘ │                               │
│  │  ┌───────────────────────────────────────────────────┐  │                               │
│  │  │          ElastiCache Redis (Cluster)              │  │                               │
│  │  └───────────────────────────────────────────────────┘  │                               │
│  └────────────────────────────────────────────────────────┘                               │
└────────────────────────────────────────────────────────────────────────────────────────────┘

                    S3 (Static Assets / Terraform State)
                    CloudWatch + CloudTrail (모니터링/감사)
                    SNS (알림)
                    IAM (권한 관리)
                    ACM (SSL/TLS 인증서)
                    Secrets Manager (DB 패스워드 등 민감정보)
```

---

## 학습 로드맵

### Phase 1 — 네트워크 기초 (Network Foundation)
> 목표: 모든 AWS 인프라의 기반이 되는 네트워크를 직접 설계하고 구현한다

- [x] VPC 생성 (CIDR 설계)
- [x] Public / Private / DB 서브넷 (Multi-AZ)
- [x] Internet Gateway 연결
- [x] NAT Gateway (AZ별 HA 구성)
- [x] Route Table 설계 및 서브넷 연결

**체크포인트:** Public 서브넷의 EC2는 인터넷 접근이 되고, Private 서브넷의 EC2는 NAT를 통해서만 아웃바운드가 가능한가?

---

### Phase 2 — 보안 계층 (Security Layer)
> 목표: 최소 권한 원칙(Least Privilege)에 기반한 보안 구성을 이해하고 구현한다

- [x] Security Group 계층 설계 (ALB → App → DB)
- [x] Network ACL 구성
- [x] IAM Role / Policy 설계 (EC2 Instance Profile)
- [ ] S3 버킷 정책 (퍼블릭 차단, VPC endpoint)
- [x] Secrets Manager로 DB 패스워드 관리
- [x] ACM으로 SSL 인증서 발급

**체크포인트:** DB 서브넷에는 App 서버에서만 접근 가능하고, 외부에서 직접 접근이 차단되는가?

---

### Phase 3 — 웹 티어 (Web Tier)
> 목표: 글로벌 트래픽을 안정적으로 수용하는 엔트리포인트를 구축한다

- [ ] ACM 인증서 연결 (HTTPS)
- [x] Application Load Balancer (ALB) 구성
- [x] ALB 리스너 규칙 (HTTP → HTTPS 리다이렉트)
- [x] CloudFront 배포 (오리진: ALB)
- [x] WAF Web ACL 연결 (기본 룰셋 적용)
- [ ] Route 53 레코드 연결 (Alias)

**체크포인트:** `https://` 도메인으로 접근 시 CloudFront → ALB → App 흐름이 정상 동작하는가?

---

### Phase 4 — 앱 티어 (Application Tier)
> 목표: 트래픽에 따라 자동으로 확장/축소되는 탄력적인 앱 서버를 구현한다

- [x] Launch Template 작성 (AMI, 인스턴스 타입, User Data)
- [x] Auto Scaling Group 구성 (Min/Max/Desired)
- [x] ALB Target Group 연결
- [x] Scaling Policy (CPU 기반 Target Tracking)
- [x] EC2 Instance Profile (IAM Role 연결)
- [x] Session Manager (Bastion 없이 접속)

**체크포인트:** 부하 발생 시 인스턴스가 자동으로 늘어나고, ALB가 트래픽을 고르게 분산하는가?

---

### Phase 5 — 데이터베이스 티어 (Database Tier)
> 목표: 고가용성과 데이터 안전성을 갖춘 데이터베이스 계층을 구성한다

- [x] RDS Subnet Group 생성
- [x] RDS Aurora MySQL (Multi-AZ, Primary + Replica)
- [x] RDS 파라미터 그룹 / 옵션 그룹
- [x] ElastiCache Subnet Group 생성
- [x] ElastiCache Redis (클러스터 모드)
- [x] 자동 백업 및 스냅샷 정책
- [x] Secrets Manager 연동 (패스워드 자동 로테이션)

**체크포인트:** App 서버에서 RDS와 Redis에 정상 연결되고, Primary 장애 시 자동 Failover가 되는가?

---

### Phase 6 — 모니터링 & 관찰성 (Observability)
> 목표: 문제를 사전에 감지하고 빠르게 대응할 수 있는 운영 환경을 갖춘다

- [ ] CloudWatch 대시보드 구성
- [ ] CloudWatch Alarms (CPU, 메모리, 에러율, 응답시간)
- [ ] SNS 토픽 및 구독 (이메일 알림)
- [ ] ALB Access Log → S3 저장
- [ ] CloudTrail 활성화 (API 감사 로그)
- [ ] CloudWatch Logs (App 로그 수집)
- [ ] CloudWatch Insights 쿼리

**체크포인트:** 이상 징후 발생 시 이메일로 알림이 오고, 대시보드에서 시스템 상태를 한눈에 파악 가능한가?

---

### Phase 7 — IaC 고도화 (Terraform Best Practices)
> 목표: 팀에서 실제로 사용 가능한 수준의 Terraform 코드를 작성한다

- [x] Remote Backend 구성 (S3 + DynamoDB State Lock)
- [ ] 환경 분리 (dev / staging / prod)
- [x] 재사용 가능한 모듈 구조 설계
- [ ] `terraform.tfvars` 환경별 분리 (`.gitignore` 적용)
- [x] `data source` 활용 (AMI 최신 버전 자동 참조 등)
- [x] `locals`, `count`, `for_each` 활용
- [ ] `terraform fmt`, `terraform validate`, `tfsec` CI 적용

**체크포인트:** `terraform apply`로 dev 환경과 prod 환경을 별도 State로 독립적으로 관리할 수 있는가?

---

## 폴더 구조 (최종 목표)

```
terraform-practice/
├── bootstrap/                  ← Terraform 없음, AWS CLI 스크립트만 사용
│   └── init.sh                 ← S3 버킷 + DynamoDB 테이블 생성 (멱등성 보장)
│
├── modules/                    ← 재사용 가능한 모듈 모음
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security_groups/
│   ├── alb/
│   ├── cloudfront/
│   ├── asg/
│   ├── rds/
│   ├── elasticache/
│   ├── monitoring/
│   └── iam/
│
├── envs/
│   ├── dev/
│   │   ├── 1-network/          ← State: dev/1-network/terraform.tfstate
│   │   │   ├── main.tf         ← module "vpc" { source = "../../../modules/vpc" }
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf      ← vpc_id, subnet_ids 등 노출
│   │   │   ├── providers.tf
│   │   │   ├── backend.tf      ← S3 backend 참조
│   │   │   └── terraform.tfvars
│   │   ├── 2-security/         ← State: dev/2-security/terraform.tfstate
│   │   ├── 3-web/              ← State: dev/3-web/terraform.tfstate
│   │   ├── 4-app/              ← State: dev/4-app/terraform.tfstate
│   │   ├── 5-database/         ← State: dev/5-database/terraform.tfstate
│   │   └── 6-monitoring/       ← State: dev/6-monitoring/terraform.tfstate
│   │
│   └── prod/
│       ├── 1-network/          ← State: prod/1-network/terraform.tfstate
│       ├── 2-security/
│       ├── 3-web/
│       ├── 4-app/
│       ├── 5-database/
│       └── 6-monitoring/
│
└── README.md
```

### 레이어 간 데이터 전달

각 레이어는 독립된 State를 가지므로, 상위 레이어의 출력값은 `terraform_remote_state`로 참조한다.

```hcl
# envs/dev/4-app/iam.tf 예시
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "dev/1-network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

module "asg" {
  source     = "../../../modules/asg"
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}
```

### 실행 순서

```
# 1. 최초 1회 — Remote Backend 생성 (S3/DynamoDB가 없을 때만 실행)
bash bootstrap/init.sh

# 2. 이후 레이어 순서대로
cd envs/dev/1-network    && terraform init && terraform apply
cd envs/dev/2-security   && terraform init && terraform apply
cd envs/dev/3-web        && terraform init && terraform apply
cd envs/dev/4-app        && terraform init && terraform apply
cd envs/dev/5-database   && terraform init && terraform apply
cd envs/dev/6-monitoring && terraform init && terraform apply
```

### 신규 팀원 온보딩

```
1. git clone
2. AWS credentials 설정 (aws configure)
3. S3/DynamoDB가 이미 존재하므로 bootstrap 실행 불필요
4. 바로 terraform init 시작 가능

※ S3/DynamoDB가 없는 경우(최초 세팅)에만 bash bootstrap/init.sh 실행
```

---

## 진행 현황

| Phase | 내용 | 상태 |
|-------|------|------|
| Phase 1 | Network Foundation | ✅ 완료 |
| Phase 2 | Security Layer | 🔄 진행중 (5/6) |
| Phase 3 | Web Tier | 🔄 진행중 (4/6) |
| Phase 4 | Application Tier | ✅ 완료 |
| Phase 5 | Database Tier | ✅ 완료 |
| Phase 6 | Observability | 🔲 미시작 |
| Phase 7 | IaC Best Practices | 🔄 진행중 (4/7) |

---

## 평가

작업한 Terraform 코드의 완성도를 평가받으려면 아래 명령어를 사용하세요.

```
/tf-review
```

현재 Phase, 체크포인트 달성 여부, 개선 사항을 분석해드립니다.
