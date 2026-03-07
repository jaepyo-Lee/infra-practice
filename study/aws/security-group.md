# Security Group

> 마지막 업데이트: 2026-03-07 (SG outbound 의미, Stateful 오개념 교정 추가)

---

## 1. 개념 설명

### Security Group이란?

AWS 리소스(EC2, RDS, ALB 등)에 붙이는 **인스턴스 수준 가상 방화벽**이다.
인바운드(들어오는)와 아웃바운드(나가는) 트래픽을 포트/프로토콜/출처 단위로 허용/차단한다.

### 핵심 특성: Stateful

연결 상태를 기억한다. 인바운드 요청이 허용되면, 그 연결의 응답 패킷은 아웃바운드 규칙 없이 자동 허용된다.

```
클라이언트 → EC2 (Port 80 인바운드 허용)
EC2 → 클라이언트 응답 ← 아웃바운드 규칙 없어도 자동 허용 ✅
```

NACL(Stateless)과 다른 핵심 차이다. SG는 응답 트래픽을 별도로 열 필요가 없다.

#### Stateful 오개념 교정

"SG outbound 기본값이 전체 허용(`0.0.0.0/0`)이라서 응답이 자동으로 나가는 것 아닌가?"
→ **아니다.** outbound를 전부 차단(`deny all`)해도, inbound로 들어온 연결의 응답은 자동으로 나간다.
이것이 Stateful의 진짜 의미: **연결 상태(Connection Tracking)를 추적**해서 응답 패킷을 outbound 규칙 평가 없이 통과시킨다.

#### SG outbound의 실제 의미

SG outbound는 **이 EC2가 먼저 요청을 시작할 때** 제어한다.

| 상황 | outbound 필요 여부 |
|------|-----------------|
| 클라이언트 → EC2 80 요청의 응답 | ❌ 불필요 (Stateful이 처리) |
| EC2 → RDS 3306 연결 | ✅ outbound 3306 허용 필요 |
| EC2 → 외부 API 443 호출 | ✅ outbound 443 허용 필요 |

SG의 기본 outbound `0.0.0.0/0 ALL ALLOW`는 편의를 위한 기본값이지, Stateful의 근거가 아니다.
최소 권한 원칙을 따르려면 outbound도 필요한 포트만 명시해야 한다.

### 허용만 가능, 거부 규칙은 없다

SG는 **화이트리스트 방식**이다. 규칙에 없는 트래픽은 기본 차단된다.
명시적 거부(Deny) 규칙은 만들 수 없다.

```
규칙 목록에 없는 트래픽 → 자동 DROP (명시 불필요)
규칙 목록에 있는 트래픽 → ALLOW
```

### SG ID를 출처(Source)로 지정 — 이것이 핵심

IP 주소 대신 **다른 SG의 ID를 출처로 지정**할 수 있다. 이것이 AWS Security Group의 가장 중요한 기능이다.

```
DB SG 인바운드 규칙:
  Port 3306  출처: sg-0abc1234 (App SG ID)  ← IP가 아닌 SG 참조
```

왜 이것이 강력한가?
- App 서버가 오토스케일링으로 IP가 바뀌어도 규칙 수정 불필요
- `0.0.0.0/0`(전체 허용)을 쓰지 않아도 됨
- "App SG가 붙은 인스턴스만 허용"이라는 **의미 기반 규칙**이 가능

---

### 이 프로젝트의 3계층 SG 설계

```
인터넷
  ↓
┌─────────────────────────────┐
│  ALB SG                     │
│  Inbound:  0.0.0.0/0 → 80  │  ← 모든 곳에서 HTTP
│            0.0.0.0/0 → 443 │  ← 모든 곳에서 HTTPS
│  Outbound: App SG → 8080   │  ← App 서버로만
└─────────────────────────────┘
  ↓
┌─────────────────────────────┐
│  App SG                     │
│  Inbound:  ALB SG → 8080   │  ← ALB에서만 수신
│  Outbound: DB SG → 3306    │  ← DB로만
│            0.0.0.0/0 → 443 │  ← 외부 API, ECR 등
└─────────────────────────────┘
  ↓
┌─────────────────────────────┐
│  DB SG                      │
│  Inbound:  App SG → 3306   │  ← App 서버에서만 수신
│  Outbound: (없음)           │  ← DB는 먼저 통신 시작 안 함
└─────────────────────────────┘
```

---

### Circular Reference (순환 참조) 문제

SG끼리 서로를 참조할 때 Terraform에서 순환 참조 오류가 발생할 수 있다.

```
ALB SG outbound → App SG 참조
App SG inbound  → ALB SG 참조
```

이 경우 SG 리소스 자체(`aws_security_group`)와 규칙(`aws_security_group_rule`)을 **분리**해서 선언하면 해결된다.
SG를 먼저 만들고, 규칙을 나중에 추가하는 방식이다.

```
1단계: aws_security_group "alb" + "app" + "db" 생성 (규칙 없이)
2단계: aws_security_group_rule 로 각 SG에 규칙 추가 (서로 참조 가능)
```

---

### Default Security Group의 함정

VPC 생성 시 Default SG가 자동 생성된다. 기본 설정은 **같은 SG 내 모든 트래픽 허용**이다.
리소스를 생성할 때 SG를 명시하지 않으면 Default SG에 붙는다 — 보안 사고의 원인.

**Best Practice**: 모든 리소스에 명시적으로 커스텀 SG를 지정하고, Default SG는 규칙을 전부 제거한다.

---

### 실무에서 자주 하는 실수

1. **DB SG에 `0.0.0.0/0` 오픈** → 인터넷 전체에서 DB 접근 가능, 치명적 보안 취약점
2. **아웃바운드 `0.0.0.0/0` 전체 허용** → 편하지만 최소 권한 원칙 위반
3. **SG를 하나로 통합** → 역할 구분이 없어 어디서 어디로 허용되는지 파악 불가
4. **Circular Reference 무시** → Terraform apply 시 오류 발생
5. **인바운드 허용 포트를 앱 포트와 다르게** → ALB가 8080으로 보내는데 SG는 80만 열린 경우

---

## 2. Terraform 핵심 파라미터

### `aws_security_group`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | ✅ | SG 이름. VPC 내에서 유일해야 함 |
| `vpc_id` | ✅ | 어느 VPC에 생성할지. 없으면 Default VPC에 생성됨 |
| `description` | 권장 | 없으면 "Managed by Terraform"이 들어감 |
| `ingress` / `egress` | 선택 | 인라인 규칙 블록 (순환 참조 시 분리 필요) |

### `aws_security_group_rule` (규칙 분리 방식 — 권장)

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `type` | ✅ | `"ingress"` 또는 `"egress"` |
| `from_port` / `to_port` | ✅ | 포트 범위. 단일 포트면 둘 다 같은 값 |
| `protocol` | ✅ | `"tcp"`, `"udp"`, `"-1"` (전체) |
| `security_group_id` | ✅ | 이 규칙이 적용될 SG ID |
| `cidr_blocks` | 선택 | IP 범위로 출처 지정 시 |
| `source_security_group_id` | 선택 | **SG ID로 출처 지정 시** — 계층 구조 구현의 핵심 |

---

## 3. Terraform 구현 참고

→ [핵심 블록 & for_each 패턴](../terraform/core-blocks.md)
→ [모듈 구조 컨벤션](../terraform/module-structure.md)

---

## 4. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 2 — Security Layer |
| 레이어 | `modules/security_groups/` |

**선행 리소스**:
- `aws_vpc` — SG는 VPC 안에 생성됨 (`vpc_id` 필수)

**후행 리소스** (사실상 모든 리소스가 SG를 참조):
- `aws_lb` (ALB) → `security_groups`
- EC2 / ECS Task → `security_groups`
- `aws_rds_cluster` → `vpc_security_group_ids`
- `aws_elasticache_replication_group` → `security_group_ids`

---

## 5. 직접 해볼 것

3계층 SG 설계도를 먼저 표로 작성해보자.

| SG 이름 | Inbound 규칙 | Outbound 규칙 |
|---------|------------|--------------|
| alb-sg  | 0.0.0.0/0:80, 0.0.0.0/0:443 | app-sg:8080 |
| app-sg  | alb-sg:8080 | db-sg:3306, 0.0.0.0/0:443 |
| db-sg   | app-sg:3306 | (없음) |

이 표를 완성한 뒤 `modules/security_groups/main.tf`에 `aws_security_group` 3개를 먼저 만들어보자.

**AWS 공식 문서**:
- [Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)
- 검색 키워드: `aws_security_group_rule terraform circular reference`, `security group source security group id terraform`
