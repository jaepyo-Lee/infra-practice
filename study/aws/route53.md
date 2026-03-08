# Route53

> 마지막 업데이트: 2026-03-08

---

## 1. 개념 설명

### Route53이란

AWS의 DNS 서비스다. 도메인 이름(`example.com`)을 IP 주소 또는 AWS 리소스로 변환해주는 역할을 한다.

DNS가 뭔지 모르면: 전화번호부와 같다. "홍길동"(도메인)을 찾으면 "010-1234-5678"(IP)을 알려준다.

### Hosted Zone이란

특정 도메인에 대한 **DNS 레코드 모음**이다. `example.com`에 대한 Hosted Zone을 만들면, Route53이 그 도메인의 DNS 서버 역할을 담당한다.

---

## 2. Public vs Private Hosted Zone

| | Public Hosted Zone | Private Hosted Zone |
|--|---|---|
| 접근 범위 | 인터넷 전체 | 특정 VPC 내부만 |
| 용도 | 외부 사용자가 접속하는 도메인 | VPC 안 서버끼리 통신하는 내부 도메인 |
| DNS 조회 | 전 세계 누구나 가능 | VPC 밖에서는 조회 불가 |
| 비용 | 월 $0.50 / Hosted Zone | 월 $0.50 / Hosted Zone |

### Public Hosted Zone — 외부 사용자용

```
사용자 (인터넷)
    ↓ example.com 입력
Route53 (Public Hosted Zone)
    ↓ A 레코드: example.com → CloudFront DNS
CloudFront → ALB → EC2
```

### Private Hosted Zone — 내부 서버 간 통신용

VPC 안에서 서버끼리 통신할 때 IP 대신 도메인을 쓰고 싶을 때 사용한다.

```
App 서버 → db.internal.example.com → RDS
           ↑
  Private Hosted Zone에만 존재
  인터넷에서는 조회 불가
```

IP 하드코딩 대신 도메인으로 참조하면, RDS 엔드포인트가 바뀌어도 앱 코드 수정이 없다.

---

## 3. DNS 레코드 타입 상세 설명

### DNS가 동작하는 원리

브라우저에 `example.com` 입력하면:

```
브라우저 → 내 컴퓨터 DNS 캐시 확인
           → 없으면 ISP DNS 서버에 질문
                → 없으면 루트 DNS → TLD DNS → NS DNS → 최종 답변
```

DNS는 결국 **"도메인 이름 → IP 주소"로 변환하는 전화번호부**다. 레코드 타입은 이 전화번호부의 항목 종류다.

---

### 루트 도메인 vs 서브도메인

```
example.com        ← 루트 도메인 (apex 도메인이라고도 함) — 구매하는 단위
www.example.com    ← 서브도메인 (별도 구매 불필요, 레코드 추가만으로 충분)
api.example.com    ← 서브도메인
dev.example.com    ← 서브도메인
```

`example.com` 하나만 구매하면 하위 서브도메인은 모두 소유자가 자유롭게 Route53에 레코드를 추가해서 사용할 수 있다.

---

### 레코드 타입별 동작 원리

**A 레코드 — 도메인 → IPv4 주소**

```
브라우저: "example.com IP 알려줘"
A 레코드: "1.2.3.4"
브라우저: 1.2.3.4로 TCP 연결 시작
```

가장 기본적인 레코드. IP가 고정된 서버(Elastic IP 붙인 EC2 등)에 연결할 때 사용.

**CNAME — 도메인 → 다른 도메인**

```
브라우저: "www.example.com IP 알려줘"
CNAME: "xxx.cloudfront.net을 찾아봐"
브라우저: "xxx.cloudfront.net IP 알려줘" (재조회)
A 레코드: "1.2.3.4"
```

IP 대신 다른 도메인을 가리킨다. CloudFront처럼 IP가 수시로 바뀌는 서비스를 서브도메인에 연결할 때 유용. **루트 도메인에는 사용 불가** (DNS 표준 제약).

> **CNAME이 루트 도메인에 안 되는 이유**: 루트 도메인에는 NS, MX 같은 레코드가 반드시 공존해야 한다. DNS 표준상 CNAME이 있는 이름에는 다른 레코드가 공존할 수 없어서, 루트 도메인에 CNAME을 넣으면 NS가 사라져 도메인 전체가 동작 불능이 된다.

**Route53 Alias — CNAME의 루트 도메인 제약을 해결한 AWS 전용 기능**

```
example.com → Alias → xxx.cloudfront.net   ✅ 루트 도메인에서 가능
```

타입이 A처럼 보이지만, Route53이 내부에서 CloudFront/ALB의 현재 IP를 실시간으로 조회해서 응답한다. **AWS 리소스(ALB, CloudFront, API Gateway)는 거의 항상 Alias를 사용한다.**

```hcl
alias {
  name                   = aws_cloudfront_distribution.main.domain_name
  zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
  evaluate_target_health = false  # CloudFront는 health check 미지원
}
```

**NS — 이 도메인 담당 네임서버가 누구야?**

```
인터넷: "example.com 누가 관리해?"
NS 레코드: "ns-123.awsdns-01.com이 관리함"
인터넷: (awsdns 서버에게) "example.com IP 알려줘"
```

DNS 질의가 어느 서버로 가야 하는지 알려주는 출발점. 없으면 아무도 도메인을 찾을 수 없다. 보통 자동 생성되므로 직접 건드릴 일 거의 없음.

**TXT — 소유권 증명 / 이메일 설정**

```
ACM: "example.com 소유자임을 증명해. 이 값을 DNS에 추가해봐"
소유자: Route53에 TXT 레코드 추가
ACM: (확인 후) 인증서 발급
```

DNS에 특정 값을 추가할 수 있다 = 도메인 소유자라는 증명. ACM 인증서 발급 시 자동으로 추가됨.

---

### 레코드 타입 선택 기준

```
가리키는 대상이 IP 주소?
  → A 레코드

가리키는 대상이 도메인이고, 서브도메인?
  → CNAME

가리키는 대상이 도메인이고, 루트 도메인? 또는 AWS 리소스(ALB, CloudFront)?
  → Alias (A 타입)

도메인 소유권 증명 / 이메일 설정?
  → TXT
```

---

### 시나리오별 레코드 예시

| 상황 | 레코드 타입 | 이유 |
|------|-----------|------|
| `example.com` → CloudFront | A (Alias) | 루트 도메인 + IP 고정 안됨 |
| `www.example.com` → CloudFront | CNAME 또는 A (Alias) | 서브도메인은 CNAME 가능 |
| `api.example.com` → ALB | A (Alias) | AWS 리소스는 Alias |
| `example.com` → EC2 Elastic IP | A | IP 고정이므로 그냥 A |
| ACM 인증서 검증 | CNAME | ACM이 지정한 값 등록 |

---

## 5. NS 레코드 위임 — 외부 도메인 업체와 연결하는 방법

도메인을 가비아, 후이즈 등 외부 업체에서 구입한 경우, Route53이 DNS를 관리하려면 **NS 레코드 위임**이 필요하다.

```
1. Route53에 Hosted Zone 생성
        ↓
2. NS 레코드 4개 자동 발급
   예: ns-123.awsdns-45.com
       ns-456.awsdns-67.net
       ...
        ↓
3. 외부 도메인 업체 설정 페이지에서
   기존 NS를 Route53 NS로 교체
        ↓
4. 이후 모든 DNS 쿼리가 Route53으로 전달됨
   → Terraform으로 레코드 자동 관리 가능
```

위임하지 않으면 Terraform이 Route53에 레코드를 추가해도 실제 DNS에 반영되지 않는다.

---

## 4. VPC DNS Resolver와 PHZ 동작 원리

### 구분의 주체: VPC DNS Resolver

Public ALB와 Private ALB의 DNS를 구분하는 주체는 **VPC DNS Resolver**다.

```
주소: 169.254.169.253 (또는 VPC CIDR의 +2번째 주소, 예: 10.0.0.2)
역할: VPC 내부의 모든 DNS 쿼리를 받는 첫 번째 창구
특징: AWS가 모든 VPC에 자동 제공, 별도 설치/설정 불필요
```

VPC에서 DNS가 동작하려면 두 설정이 true여야 한다:
```hcl
resource "aws_vpc" "main" {
  enable_dns_support   = true  # VPC DNS Resolver 활성화
  enable_dns_hostnames = true  # 인스턴스에 DNS 이름 부여
}
```

### PHZ 우선순위

VPC DNS Resolver의 조회 순서:
```
1. PHZ (이 VPC에 연결된 Private Hosted Zone) ← 먼저 확인
2. Public Hosted Zone                          ← PHZ에 없을 때
3. 인터넷 DNS (외부 도메인)                    ← 그 다음
```

PHZ가 VPC에 **associate(연결)** 되어 있으면, 같은 도메인이라도 VPC 내부에서는 PHZ 결과가 Public HZ를 덮어씌운다.

### DNS 전체 조회 흐름

**인터넷 사용자가 `api.example.com` 조회하는 경우:**

```
[사용자 PC]
    │ "api.example.com의 IP가 뭐야?"
    ▼
[ISP DNS 서버 / 8.8.8.8]
    │ "모르면 Root DNS에게 물어봐"
    ▼
[Root DNS] → ".com 담당 서버한테 물어봐"
    ▼
[.com DNS] → "example.com은 Route53이 담당해"
    ▼
[Route53 — Public Hosted Zone]
    │ PHZ는 여기서 보이지 않음 (VPC 밖이라)
    │ api.example.com → 57.x.x.x (Public ALB IP)
    ▼
[사용자 PC] → 57.x.x.x로 접속
```

**VPC 내부 EC2가 동일한 도메인 조회하는 경우:**

```
[VPC 내부 EC2]
    │ "api.example.com의 IP가 뭐야?"
    ▼
[VPC DNS Resolver] ← 여기서 구분이 일어남
    │ "이 VPC에 연결된 PHZ 먼저 확인"
    │ api.example.com → 10.0.1.x (Private ALB IP) ← PHZ에서 찾음
    ▼
[EC2] → 10.0.1.x로 접속 (인터넷 안 나감, VPC 내부에서 해결)
```

### Split-horizon DNS

같은 도메인이 **조회 위치에 따라 다른 IP를 반환**하는 패턴이다.

```
api.example.com
  인터넷에서 조회 → 57.x.x.x  (Public ALB)
  VPC 안에서 조회 → 10.0.1.x  (Private ALB)
```

**장점:**
- 내부 서비스끼리 인터넷을 경유하지 않음 → 레이턴시 감소, 데이터 전송 비용 절감
- 외부에는 Public ALB의 WAF/보안 계층을 통하게 함
- 앱 코드는 같은 도메인을 사용 → 환경 별 분기 불필요

---

## 5. 이 프로젝트에서의 역할

```
Public Hosted Zone  → example.com
  ├── A (Alias)     → CloudFront (외부 사용자 접속)
  ├── A (Alias)     → ALB (api.example.com)
  └── CNAME         → ACM 검증 레코드 (인증서 발급용)

Private Hosted Zone → internal.example.com
  ├── CNAME         → RDS 엔드포인트 (App → DB)
  └── CNAME         → ElastiCache 엔드포인트 (App → Redis)
```

Private Hosted Zone은 필수는 아니지만 실무에서 많이 쓴다. RDS/ElastiCache 엔드포인트를 내부 도메인으로 추상화하면 교체 시 앱 코드 수정이 없다.

**Phase 3 (Web Tier)** 에서 구현한다.

→ [ACM 인증서 및 DNS 검증](./acm.md)
→ [핵심 블록 & for_each](../terraform/core-blocks.md)
