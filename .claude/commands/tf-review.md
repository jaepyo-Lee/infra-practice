# Terraform 구현 평가 (tf-review)

현재 프로젝트의 Terraform 코드를 분석하여 README.md에 정의된 학습 목표 달성 여부를 평가한다.

## 중요 원칙

**코드를 대신 작성하지 않는다.**
사용자가 직접 구현하며 학습하는 것이 목표이므로, 평가 결과에서 개선이 필요한 항목은 반드시 **힌트와 방향만 제시**한다.
- 완성된 코드 블록을 제공하지 않는다
- 어떤 리소스/속성을 써야 하는지 키워드 수준으로만 안내한다
- 막힌 부분이 있으면 공식 문서 링크나 검색 키워드를 제안한다
- **예외**: 사용자가 명시적으로 "작성해줘" 등 코드 작성을 요청하면 작성 가능

## 평가 절차

아래 순서대로 진행하라:

### 1. 현재 상태 파악
- 프로젝트 루트의 파일/폴더 구조를 먼저 파악한다 (Glob 사용)
- 모든 `.tf` 파일을 읽어 구현된 리소스 목록을 수집한다
- `README.md`의 Phase별 체크리스트와 대조한다

### 2. Phase별 달성도 평가

각 Phase에 대해 다음을 확인한다:

**Phase 1 — Network Foundation**
- VPC 리소스 존재 여부 (`aws_vpc`)
- Public/Private/DB 서브넷이 최소 2개 AZ에 걸쳐 있는지 (`aws_subnet`)
- Internet Gateway 연결 (`aws_internet_gateway`)
- NAT Gateway 존재 및 AZ별 분리 여부 (`aws_nat_gateway`)
- Route Table 구성 및 서브넷 연결 (`aws_route_table`, `aws_route_table_association`)
- VPC Flow Logs 여부 (`aws_flow_log`)

**Phase 2 — Security Layer**
- Security Group 계층 구조 (ALB용 / App용 / DB용 분리 여부)
- Network ACL 존재 여부 (`aws_network_acl`)
- IAM Role/Policy 존재 여부 (`aws_iam_role`)
- Secrets Manager 사용 여부 (`aws_secretsmanager_secret`)
- ACM 인증서 여부 (`aws_acm_certificate`)

**Phase 3 — Web Tier**
- ALB 구성 (`aws_lb`, `aws_lb_listener`)
- HTTPS 리스너 + HTTP → HTTPS 리다이렉트 규칙
- CloudFront 배포 (`aws_cloudfront_distribution`)
- WAF 연결 (`aws_wafv2_web_acl`)
- Route 53 레코드 (`aws_route53_record`)

**Phase 4 — Application Tier**
- Launch Template (`aws_launch_template`)
- Auto Scaling Group (`aws_autoscaling_group`)
- Scaling Policy (`aws_autoscaling_policy`)
- Target Group 및 ALB 연결

**Phase 5 — Database Tier**
- RDS Subnet Group (`aws_db_subnet_group`)
- RDS Aurora 클러스터 + 인스턴스 (`aws_rds_cluster`, `aws_rds_cluster_instance`)
- ElastiCache Subnet Group + Redis (`aws_elasticache_replication_group`)
- 백업 설정 여부 (backup_retention_period)

**Phase 6 — Observability**
- CloudWatch Alarms (`aws_cloudwatch_metric_alarm`)
- SNS Topic/Subscription (`aws_sns_topic`)
- CloudTrail (`aws_cloudtrail`)
- CloudWatch Log Groups (`aws_cloudwatch_log_group`)

**Phase 7 — IaC Best Practices**
- Remote Backend 설정 (`backend "s3"`)
- 모듈 구조 사용 여부 (`module` 블록)
- 환경 분리 구조 (`envs/dev`, `envs/prod`)
- `locals`, `for_each`, `count` 활용 여부
- `data` 소스 활용 여부

### 3. 환경 분리 평가

dev/prod 환경 분리가 올바르게 구현되어 있는지 확인한다:

**폴더 구조**
- `envs/dev/`, `envs/prod/` 디렉토리가 존재하는지
- 각 환경 폴더에 `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `backend.tf`, `terraform.tfvars`가 있는지

**Backend 분리**
- 환경별로 S3 key 경로가 다른지 (예: `dev/terraform.tfstate` vs `prod/terraform.tfstate`)
- DynamoDB State Lock 테이블이 설정되어 있는지
- 환경별로 서로 다른 AWS 계정 또는 프로파일을 사용하는지 (선택)

**변수 분리**
- 환경별 `terraform.tfvars`에 인스턴스 타입, 용량, 도메인 등이 다르게 설정되어 있는지
  - 예: dev는 `t3.micro`, prod는 `t3.medium`
  - 예: dev는 NAT Gateway 1개, prod는 AZ별 NAT Gateway
- 민감한 값(패스워드, API Key)이 `.tfvars`에 하드코딩되지 않고 Secrets Manager 또는 환경변수로 처리되는지

**공통 리소스 관리**
- `envs/shared/` 또는 별도 구조로 공통 리소스(Route53, ACM, ECR 등)가 분리되어 있는지

---

### 4. 모듈 재사용성 평가

`modules/` 디렉토리의 구조와 코드 재사용성을 평가한다:

**모듈 구조 완성도**
- 각 모듈 폴더에 `main.tf`, `variables.tf`, `outputs.tf`가 모두 있는지
- `modules/` 폴더를 Glob으로 직접 탐색해 실제 존재하는 모듈 목록을 확인한다 (하드코딩된 목록 대신)
- 탐색한 모듈 목록을 README.md의 모듈 체크리스트와 대조한다
- 참고 예시 (프로젝트 진행에 따라 달라질 수 있음):
  - `modules/network/` (vpc → network로 리팩토링됨)
  - `modules/security/` (SG, NACL, IAM, Secrets Manager, ACM, S3 통합)
  - `modules/web/` (ALB, CloudFront, WAF 통합)
  - `modules/app/` (Launch Template, ASG, Scaling Policy 통합)
  - `modules/database/` (RDS Aurora + ElastiCache 통합)
  - `modules/monitoring/`

**모듈 인터페이스 품질**
- `variables.tf`에 모든 입력값이 `type`, `description`, `default`(선택)와 함께 선언되어 있는지
- `outputs.tf`에 다른 모듈이 참조할 수 있는 값들이 노출되어 있는지 (예: VPC ID, 서브넷 ID, SG ID)
- 모듈 내부에 환경별 분기 로직이 없는지 (모듈은 환경 무관하게 동작해야 함)

**모듈 호출 방식**
- `envs/dev/main.tf`에서 `module "vpc" { source = "../../modules/vpc" ... }` 형태로 호출하는지
- 모듈 버전이 고정되어 있는지 (로컬 모듈이라면 해당 없음, 공개 모듈이면 `version` 필수)
- 같은 모듈을 dev/prod 양쪽에서 재사용하는지 (코드 중복 없이)

**고급 재사용 패턴**
- `for_each`나 `count`로 반복 리소스를 처리하는지 (예: 서브넷 여러 개 생성)
- `locals`로 공통 태그나 네이밍 규칙을 중앙화했는지
- `data` 소스로 외부 정보를 동적 참조하는지 (예: `data "aws_ami" "amazon_linux"`)

---

### 5. 코드 품질 검토

- 하드코딩된 값이 있는지 (IP, 패스워드, 계정 ID, 리전 등) → 변수화 권장
- 보안 취약점: Security Group에 `0.0.0.0/0` inbound가 불필요하게 열려있는지
- `terraform.tfvars`가 `.gitignore`에 포함되어 있는지
- 모든 리소스에 `tags`가 일관되게 적용되어 있는지 (Environment, Project, ManagedBy 등)
- 변수에 `description`과 `type`이 명시되어 있는지

---

### 6. 점수 계산

평가 결과를 출력하기 전에 아래 기준으로 점수를 계산한다.

#### 점수 배점표 (총 100점)

**A. Phase 달성도 (56점) — Phase당 8점**

각 Phase의 체크 항목 중 달성한 비율로 점수를 산정한다.
- Phase 항목 전부 달성 = 8점
- 일부 달성 = 8 × (달성 항목 수 / 전체 항목 수)
- 미시작 = 0점

| Phase | 배점 | 항목 수 |
|-------|------|--------|
| Phase 1 — Network Foundation | 8점 | 6개 |
| Phase 2 — Security Layer | 8점 | 5개 |
| Phase 3 — Web Tier | 8점 | 5개 |
| Phase 4 — Application Tier | 8점 | 4개 |
| Phase 5 — Database Tier | 8점 | 4개 |
| Phase 6 — Observability | 8점 | 4개 |
| Phase 7 — IaC Best Practices | 8점 | 5개 |

**B. 모듈 품질 (24점)**

| 항목 | 배점 | 기준 |
|------|------|------|
| 파일 구조 완성도 | 6점 | 구현된 모듈 중 main/variables/outputs 3파일 완비 비율 |
| variables.tf 품질 | 6점 | type + description 모두 명시, 의미있는 description |
| outputs.tf 완성도 | 6점 | 필요한 값이 모두 노출되고 value가 채워져 있음 |
| 고급 패턴 활용 | 6점 | for_each, locals, data 소스 중 활용한 수 × 2점 |

**C. IaC Best Practices (20점)**

| 항목 | 배점 | 기준 |
|------|------|------|
| Remote Backend (S3 + DynamoDB) | 5점 | backend.tf 존재 + encrypt + dynamodb_table 설정 |
| 환경 분리 구조 | 4점 | envs/dev, envs/prod 구조 + key 경로 분리 |
| .gitignore 설정 | 3점 | tfstate, tfvars 포함 여부 |
| tags 일관성 | 4점 | 모든 리소스에 Environment, ManagedBy 등 공통 태그 |
| provider 버전 고정 | 2점 | ~> 형태로 메이저 버전 고정 + required_version 명시 |
| default_tags 활용 | 2점 | provider 수준에서 공통 태그 자동 적용 |

#### 등급 기준

| 점수 | 등급 | 의미 |
|------|------|------|
| 90~100 | S | Production-Ready 수준 |
| 75~89 | A | 실무 투입 가능 수준 |
| 60~74 | B | 핵심 기능 구현 완료 |
| 45~59 | C | 기초 구조 이해 중 |
| 30~44 | D | 개념 학습 초기 단계 |
| 0~29 | F | 시작 단계 |

---

### 7. 평가 결과 출력

아래 형식으로 결과를 출력한다:

```
## Terraform 구현 평가 결과

### 종합 점수
┌─────────────────────────────────┐
│  총점: XX / 100점   등급: [S/A/B/C/D/F]  │
│                                 │
│  A. Phase 달성도   XX / 56점    │
│  B. 모듈 품질      XX / 24점    │
│  C. Best Practices XX / 20점    │
└─────────────────────────────────┘

### 현재 진행 Phase: [Phase N — 이름]

### Phase별 달성도
| Phase | 달성도 | 점수 | 구현된 리소스 수 |
|-------|--------|------|----------------|
| Phase 1 | ✅ 완료 / 🔄 진행중 / 🔲 미시작 | X.X/8 | N/M |
...

### 상세 체크리스트
[각 Phase별로 ✅/❌ 체크리스트 출력]

### 모듈 품질 점수
| 항목 | 점수 | 비고 |
|------|------|------|
| 파일 구조 완성도 | X/6 | |
| variables.tf 품질 | X/6 | |
| outputs.tf 완성도 | X/6 | |
| 고급 패턴 활용 | X/6 | |

### IaC Best Practices 점수
| 항목 | 점수 | 비고 |
|------|------|------|
| Remote Backend | X/5 | |
| 환경 분리 구조 | X/4 | |
| .gitignore | X/3 | |
| tags 일관성 | X/4 | |
| provider 버전 고정 | X/2 | |
| default_tags | X/2 | |

### 모듈 재사용성 평가
| 모듈 | 존재 여부 | variables.tf | outputs.tf | 재사용성 |
|------|----------|-------------|-----------|---------|
| vpc | ✅/❌ | ✅/❌ | ✅/❌ | 상/중/하 |
...

### 잘된 점
- [구체적으로 칭찬할 부분]

### 개선이 필요한 부분
- [우선순위 높은 순으로 구체적인 개선 제안]

### 다음 단계 가이드
현재 Phase에서 아직 구현하지 않은 항목 중 가장 먼저 해야 할 것:
1. [구체적인 작업 + 힌트]
```

모든 피드백은 학습자의 성장을 격려하는 톤으로, 구체적이고 실행 가능하게 제공한다.

---

## README.md 자동 업데이트

평가 결과 출력 후, **항상** `README.md`를 아래 규칙에 따라 업데이트한다.

### 업데이트 대상

**1. Phase별 체크리스트 (`- [ ]` → `- [x]`)**

README.md의 각 Phase 체크리스트에서 구현이 확인된 항목을 `- [x]`로 변경한다.

```
- [ ] VPC 생성 (CIDR 설계)     ← aws_vpc 리소스 존재 시 → - [x] VPC 생성 (CIDR 설계)
- [ ] Internet Gateway 연결    ← aws_internet_gateway 존재 시 → - [x]
```

**2. 진행 현황 테이블 상태 업데이트**

README.md 하단의 "진행 현황" 테이블을 실제 구현 상태로 갱신한다.

| 조건 | 상태 |
|------|------|
| 해당 Phase 항목 중 하나도 없음 | `🔲 미시작` |
| 일부 항목 구현됨 | `🔄 진행중 (N/M)` |
| 모든 항목 구현됨 | `✅ 완료` |

### 업데이트 원칙

- 이미 `- [x]`인 항목은 건드리지 않는다 (퇴보 방지)
- 구현이 확인되지 않은 항목은 `- [ ]`를 유지한다
- README.md 수정 후 "README.md 업데이트 완료" 한 줄로 알린다

---

## Best Practice 자동 수정 모드

`/tf-review` 실행 시 인수(ARGUMENTS)에 다음 키워드가 포함된 경우 이 모드로 동작한다:
- `fix`, `수정`, `best practice`, `best-practice`, `고쳐`, `만들어줘`

### 이 모드에서만 코드 직접 작성이 허용된다

평가 모드와 달리, 이 모드에서는 실제 파일을 수정한다.

### 수정 절차

1. **현재 파일 전부 읽기** — 모든 `.tf` 파일을 읽어 문제를 파악한다
2. **Best Practice 기준 적용** — 아래 기준으로 각 파일을 수정한다
3. **주석 필수 작성** — 모든 수정 사항에 왜 이렇게 했는지 주석으로 설명한다
4. **수정 결과 요약 출력** — 어떤 파일을 왜 수정했는지 목록으로 정리한다

### Best Practice 수정 기준

**파일 구조**
- `modules/*/` 폴더는 반드시 `main.tf`, `variables.tf`, `outputs.tf`로 분리한다
- `envs/*/` 폴더는 terraform 설정, provider, module 호출만 포함한다
- 리소스를 직접 `envs/`에 선언하지 않는다

**variables.tf**
- 모든 variable에 `type`과 `description`을 명시한다
- 필수값은 `default`를 생략하여 호출자가 반드시 전달하도록 강제한다
- 선택값은 `default`를 명시한다
- description은 "cidr", "vpc" 같은 단어 반복이 아닌 실제 용도와 예시를 포함한다

**outputs.tf**
- 다른 모듈이 참조할 값을 모두 노출한다 (VPC: `vpc_id`, `vpc_cidr_block`)
- 출력 이름은 `리소스_속성` 형태로 명확하게 짓는다 (예: `vpc_id`, `subnet_ids`)
- `value = ""`처럼 빈 값은 실제 리소스 속성으로 채운다

**main.tf (모듈)**
- AWS 권장 옵션을 명시적으로 작성한다 (VPC: `enable_dns_support`, `enable_dns_hostnames`)
- `tags`는 `merge()`를 사용해 공통 태그 + 리소스별 Name 태그를 합산한다

**main.tf (envs)**
- `required_version`은 `>= 1.5.0` 이상을 권장한다
- provider `version`은 `~> 5.0` 형태로 메이저 버전을 고정한다
- `default_tags`를 provider에 설정해 모든 리소스에 자동 태그를 적용한다
- `source`는 파일(`.tf`)이 아닌 디렉토리 경로를 가리킨다

**versions.tf (modules)**
- `terraform {}` 블록 (required_providers, required_version)은 리소스 파일이 아닌 `versions.tf`로 분리한다
- provider alias를 받는 모듈에는 `configuration_aliases = [aws.us_east_1, ...]` 를 선언한다
- 모든 레이어/모듈의 provider 버전이 통일되어 있는지 확인한다 (하나만 다를 경우 그 하나를 내려서 통일)

**CIDR 설계**
- VPC용 CIDR은 `/16` 이상을 사용한다 (`/24`는 단일 서브넷 크기)

**backend.tf**
- `backend` 블록은 `main.tf`가 아닌 별도 `backend.tf` 파일로 분리한다
- `encrypt = true`를 반드시 명시한다 (S3 서버 측 암호화)
- `dynamodb_table`을 반드시 설정한다 (State Lock 없으면 동시 apply 위험)
- `key` 경로는 `{환경}/{스택}/terraform.tfstate` 형태로 환경/스택별 분리한다

**Route Table 패턴**
- Route Table은 반드시 3종으로 분리한다: public-rt × 1 / private-nat-rt × AZ별 / private-full-rt × 1
- public-rt의 route: `gateway_id = aws_internet_gateway.xxx.id` (IGW로 전달)
- private-nat-rt의 route: `nat_gateway_id = aws_nat_gateway.xxx[each.key].id` (NAT GW로 전달)
  - **흔한 실수**: private-nat-rt에 `gateway_id = IGW`를 넣으면 Public IP 없는 EC2 패킷을 IGW가 처리하지 못해 아웃바운드 차단됨
- private-full-rt: `route` 블록 없음 = 인터넷 완전 차단 (VPC local 경로만 존재)
- `aws_route_table_association`으로 서브넷에 명시적 연결 필수 — 없으면 Default RT 사용

**for_each 리소스 참조 패턴**
- `for_each`로 만든 리소스는 맵(map)이므로 `.id`를 직접 참조할 수 없다
  - `aws_subnet.public.id` → ❌ 에러 (맵 전체를 단일 리소스처럼 참조)
  - `aws_subnet.public["ap-northeast-2a"].id` → ✅ (키로 특정 인스턴스 참조)
  - `each.value.id` → ✅ (for_each 블록 안에서 현재 순회 중인 인스턴스 참조)
- EIP와 NAT GW를 같은 키(AZ 이름)로 for_each하면 `aws_eip.nat[each.key].id`로 1:1 연결 가능

### 수정 결과 출력 형식

```
## Best Practice 수정 완료

### 수정된 파일 목록
| 파일 | 주요 변경 내용 |
|------|--------------|
| modules/vpc/main.tf | enable_dns_support/hostnames 추가 |
| modules/vpc/variables.tf | description 보강, default 정리 |
| modules/vpc/outputs.tf | 빈 value를 실제 리소스 속성으로 교체 |
| envs/dev/vpc/main.tf | provider 버전 업, default_tags 추가 |
| envs/dev/vpc/variables.tf | description 보강, CIDR /16 수정 |

### 핵심 학습 포인트
[수정하면서 가장 중요한 개념 2~3가지를 설명]

### 다음 단계
[수정 이후 해야 할 작업]
```
