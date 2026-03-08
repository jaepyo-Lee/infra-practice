# ALB (Application Load Balancer)

> 마지막 업데이트: 2026-03-07

---

## 1. 개념 설명

### ALB란?

Layer 7(HTTP/HTTPS) 레벨에서 동작하는 로드 밸런서다. 클라이언트 요청을 받아 백엔드 서버(EC2 등)로 분산 전달한다.

Route Table이 네트워크 레이어(L3)에서 IP 기반으로 패킷 경로를 결정하는 것과 달리, ALB는 애플리케이션 레이어(L7)에서 HTTP 경로, 헤더, 호스트명 등을 기반으로 라우팅을 결정한다.

### ALB는 리버스 프록시다 — 연결을 두 번 만든다

```
클라이언트 ─── 연결 1 ──→ ALB ─── 연결 2 ──→ EC2
(220.10.5.3)           (10.0.1.100)        (10.0.11.10)
```

ALB는 클라이언트의 연결을 끊고, EC2와 **새 연결**을 만든다. 따라서:
- EC2가 보는 요청의 출발지 IP = **ALB의 IP** (클라이언트 IP가 아님)
- 원본 클라이언트 IP는 `X-Forwarded-For` HTTP 헤더에 담겨 전달된다

```
X-Forwarded-For: 220.10.5.3   ← 원본 클라이언트 IP
X-Forwarded-Port: 443
X-Forwarded-Proto: https
```

애플리케이션에서 클라이언트 IP가 필요하면 `X-Forwarded-For` 헤더를 읽어야 한다.

### Target Group — ALB가 EC2를 아는 방법

ALB는 Route Table처럼 IP를 보고 경로를 결정하지 않는다. **Target Group**이라는 등록된 대상 목록을 보고 전달한다.

```
ALB
├── Listener (443 HTTPS)
│   └── Rules
│       ├── /api/* → Target Group A (EC2 App 서버들)
│       └── 기본  → Target Group B (EC2 Web 서버들)
│
Target Group A:
├── EC2-1 (10.0.11.10:8080)  ← 등록된 대상
├── EC2-2 (10.0.11.20:8080)
└── EC2-3 (10.0.12.10:8080)
```

**EC2가 Target Group에 등록되는 방법:**
- 수동: 인스턴스 ID 또는 IP 직접 추가
- 자동: Auto Scaling Group과 Target Group을 연결 → EC2 생성 시 자동 등록, 삭제 시 자동 해제

### Health Check

Target Group은 각 EC2에 주기적으로 헬스 체크 요청을 보낸다. 응답이 없거나 실패하면 해당 EC2로 트래픽 전달을 중단한다. 정상으로 회복되면 자동으로 다시 포함한다.

### Listener Rules

ALB Listener는 요청의 특성에 따라 다른 Target Group으로 보낼 수 있다:

| 조건 | 예시 |
|------|------|
| 경로 패턴 | `/api/*` → App 서버, `/static/*` → S3 |
| 호스트 헤더 | `api.example.com` → API 서버, `www.example.com` → Web 서버 |
| HTTP 메서드 | `POST /upload` → 별도 업로드 서버 |
| 헤더/쿼리 | 특정 헤더 값 기반 라우팅 |

### ALB Access Logs → S3 연결 구조 (두 단계 필요)

ALB 접근 로그를 S3에 저장하려면 **두 가지 설정이 모두 필요**하다:

```
1단계: S3 버킷 생성 (monitoring 모듈)
  aws_s3_bucket "alb_logs"
  aws_s3_bucket_policy  ← ELB 서비스 계정이 쓸 수 있도록 버킷 정책 필요

2단계: ALB에 버킷 연결 (web 모듈)
  resource "aws_lb" "main" {
    access_logs {
      bucket  = "버킷 이름"
      enabled = true
    }
  }
```

S3 버킷만 만들면 ALB가 자동으로 로그를 보내지 않는다.
ALB 리소스에 `access_logs` 블록을 설정해야 비로소 연결된다.

**흔한 실수**: 모니터링 모듈에서 버킷을 만들어놓고 ALB 모듈에서 연결을 빠뜨리는 경우.
이 프로젝트에서도 현재 버킷은 생성되어 있지만 ALB `access_logs` 블록이 아직 미연결 상태다.

---

### 실무에서 자주 하는 실수

1. **EC2 Security Group에 0.0.0.0/0 허용** → ALB를 거치지 않고 EC2에 직접 접근 가능. EC2 SG는 ALB SG에서 오는 트래픽만 허용해야 한다
2. **X-Forwarded-For 미처리** → 모든 요청의 출발지가 ALB IP로 찍혀 로그가 무의미해짐
3. **Target Group 헬스 체크 경로 오설정** → EC2가 정상인데 트래픽을 못 받음
4. **HTTP → HTTPS 리다이렉트 미설정** → 80 포트로 접근 시 그냥 통과되어 평문 통신

### Public ALB vs Private ALB (internal)

ALB는 두 가지 모드로 생성할 수 있다:

```
internet-facing (internal=false): 퍼블릭 IP 할당, 인터넷에서 직접 접근 가능
internal        (internal=true):  프라이빗 IP만 할당, VPC 내부에서만 접근 가능
```

```hcl
resource "aws_lb" "public" {
  internal = false  # internet-facing — 이 프로젝트 구성
}

resource "aws_lb" "private" {
  internal = true   # VPC 내부 전용
}
```

**Private ALB 사용 케이스:**

```
인터넷 → Public ALB → App 서버 → [Private ALB] → 마이크로서비스 B
                                                  → 마이크로서비스 C
```

마이크로서비스 아키텍처에서 서비스 간 트래픽 라우팅에 주로 사용한다. 외부에 노출하지 않아도 되는 내부 API 서버 앞에 놓는다.

**Private ALB + PHZ 조합:**

Private ALB의 DNS 이름은 길고 관리하기 어렵다:
```
internal-dev-alb-123456.ap-northeast-2.elb.amazonaws.com
```

Route53 Private Hosted Zone으로 짧은 내부 도메인을 부여할 수 있다:
```
api.internal → internal-dev-alb-xxx.elb.amazonaws.com
```

VPC 내부에서 `api.internal`로 요청하면 VPC DNS Resolver가 PHZ를 먼저 확인해 Private ALB IP를 반환한다. 인터넷에서는 이 도메인이 조회되지 않는다.

→ [PHZ + VPC DNS Resolver 동작 원리](./route53.md)

---

### Security Group 연결 구조 (Best Practice)

```
인터넷 → ALB SG (inbound: 80, 443 from 0.0.0.0/0)
              ↓
         EC2 SG (inbound: 8080 from ALB SG만 허용)
```

EC2 SG의 inbound source를 `0.0.0.0/0`이 아닌 **ALB SG ID**로 지정한다. 이렇게 하면 ALB를 거치지 않은 직접 접근이 차단된다.

---

## 2. Terraform 핵심 파라미터

ALB를 만들려면 리소스 4개가 필요하다:

```
aws_lb                  ← ALB 본체
aws_lb_target_group     ← 트래픽 전달 대상 그룹
aws_lb_listener         ← 포트별 수신 설정
aws_lb_listener_rule    ← 조건별 라우팅 규칙 (선택)
```

### `aws_alb` vs `aws_lb`

`aws_alb`는 `aws_lb`의 **alias(별칭)** 다. 동작은 완전히 동일하지만 공식 문서 기준 `aws_lb`가 표준이다.
`aws_alb_target_group`, `aws_alb_listener`도 마찬가지로 각각 `aws_lb_target_group`, `aws_lb_listener`가 표준이다.

---

### `aws_lb` — ALB 본체

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | 선택 | ALB 이름. 최대 32자 |
| `internal` | 선택 | `false` = 인터넷 facing (기본). `true` = 내부 전용 |
| `load_balancer_type` | 선택 | `"application"` (기본). NLB는 `"network"` |
| `subnets` | 필수 | ALB가 위치할 서브넷 ID 목록. **최소 2개 AZ 필수** |
| `security_groups` | 필수 | 연결할 SG ID 목록 |
| `enable_deletion_protection` | 선택 | `true`면 삭제 불가. 운영 환경에선 true |
| `access_logs` | 선택 | S3 버킷에 접근 로그 저장 |

> **실수 포인트**: `subnets`에 Private Subnet을 넣으면 인터넷에서 접근 불가. `internal = false`인 ALB는 반드시 Public Subnet에 위치해야 한다.

### `aws_lb_target_group` — 대상 그룹

| 인수 | 필수 | 설명 |
|------|------|------|
| `port` | 필수 | 대상이 수신하는 포트 (이 프로젝트는 8080) |
| `protocol` | 필수 | `"HTTP"` 또는 `"HTTPS"` |
| `vpc_id` | 필수 | 대상이 속한 VPC ID |
| `target_type` | 선택 | `"instance"` (기본), `"ip"`, `"lambda"` |
| `health_check` 블록 | 선택 | path, interval, threshold, matcher 등 |

**target_type과 백엔드 종류:**

| target_type | 사용 대상 | 등록 방식 |
|-------------|-----------|-----------|
| `"instance"` | EC2 (ASG) | 인스턴스 ID로 등록. ASG 연결 시 자동 등록/해제 |
| `"ip"` | ECS Fargate, ECS EC2 | Task의 ENI IP로 등록. ECS Service가 자동 관리 |
| `"lambda"` | Lambda 함수 | Lambda ARN으로 등록 |

> **ECS 사용 시 주의**: Fargate는 인스턴스가 없으므로 반드시 `target_type = "ip"` 를 써야 한다. ECS EC2 모드도 Task 단위 IP 등록을 권장한다. `"instance"`로 설정하면 Task가 아닌 호스트 EC2 전체로 트래픽이 가서 포트 충돌이 생길 수 있다.

→ [ECS 상세 개념](./ecs.md)

**health_check 주요 인수:**

| 인수 | 설명 |
|------|------|
| `path` | 헬스 체크 경로. 예: `"/health"` |
| `healthy_threshold` | 정상 판정까지 연속 성공 횟수 (기본 3) |
| `unhealthy_threshold` | 비정상 판정까지 연속 실패 횟수 (기본 3) |
| `interval` | 체크 주기(초). 기본 30 |
| `matcher` | 정상 응답 코드. 예: `"200"`, `"200-299"` |

### `aws_lb_listener` — 리스너

| 인수 | 필수 | 설명 |
|------|------|------|
| `load_balancer_arn` | 필수 | 연결할 ALB ARN |
| `port` | 필수 | 수신 포트 |
| `protocol` | 필수 | `"HTTP"` 또는 `"HTTPS"` |
| `ssl_policy` | HTTPS 시 필수 | TLS 정책. 권장: `"ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| `certificate_arn` | HTTPS 시 필수 | ACM 인증서 ARN |
| `default_action` | 필수 | `forward` / `redirect` / `fixed-response` |

**HTTP → HTTPS 리다이렉트:**
```hcl
default_action {
  type = "redirect"
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}
```

### 리소스 생성 순서 (의존 관계)

```
aws_lb_target_group
       ↓
aws_lb
       ↓
aws_lb_listener (HTTP:80 → redirect)
aws_lb_listener (HTTPS:443 → forward → target_group)
       ↓
aws_lb_listener_rule (경로별 규칙, 선택)
```

---

## 3. Terraform 구현 참고

→ [핵심 블록 & 모듈 구조](../terraform/core-blocks.md)
→ [모듈 구조 컨벤션](../terraform/module-structure.md)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 3 — Web Tier |
| 레이어 | `modules/alb/` |

**선행 리소스**:
- `aws_vpc`, `aws_subnet` (public) — ALB는 Public Subnet에 위치
- `aws_security_group` (alb-sg) — ALB에 붙일 SG

**후행 리소스**:
- `aws_autoscaling_group` — Target Group에 ASG 연결
- `aws_cloudfront_distribution` — ALB를 Origin으로 사용
- `aws_route53_record` — ALB DNS를 가리키는 레코드

---

## 4. 직접 해볼 것

Phase 3에서 ALB를 구현할 때:
- Listener 2개: 443(HTTPS) + 80→443 리다이렉트
- Target Group의 헬스 체크 경로를 `/health`로 설정하고 EC2 앱에 해당 엔드포인트 추가
- EC2 SG inbound source를 ALB SG ID로 설정

**AWS 공식 문서**:
- [Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)
- 검색 키워드: `aws_lb terraform`, `aws_lb_listener_rule`, `aws_lb_target_group health check`
