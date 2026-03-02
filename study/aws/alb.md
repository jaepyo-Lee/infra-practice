# ALB (Application Load Balancer)

> 마지막 업데이트: 2026-03-01

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

### 실무에서 자주 하는 실수

1. **EC2 Security Group에 0.0.0.0/0 허용** → ALB를 거치지 않고 EC2에 직접 접근 가능. EC2 SG는 ALB SG에서 오는 트래픽만 허용해야 한다
2. **X-Forwarded-For 미처리** → 모든 요청의 출발지가 ALB IP로 찍혀 로그가 무의미해짐
3. **Target Group 헬스 체크 경로 오설정** → EC2가 정상인데 트래픽을 못 받음
4. **HTTP → HTTPS 리다이렉트 미설정** → 80 포트로 접근 시 그냥 통과되어 평문 통신

### Security Group 연결 구조 (Best Practice)

```
인터넷 → ALB SG (inbound: 80, 443 from 0.0.0.0/0)
              ↓
         EC2 SG (inbound: 8080 from ALB SG만 허용)
```

EC2 SG의 inbound source를 `0.0.0.0/0`이 아닌 **ALB SG ID**로 지정한다. 이렇게 하면 ALB를 거치지 않은 직접 접근이 차단된다.

---

## 2. Terraform 구현 참고

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
