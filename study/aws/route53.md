# Route53

> 마지막 업데이트: 2026-03-07

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

## 3. NS 레코드 위임 — 외부 도메인 업체와 연결하는 방법

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

## 4. 이 프로젝트에서의 역할

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
