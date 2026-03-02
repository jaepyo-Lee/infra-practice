# Internet Gateway (IGW)

> 마지막 업데이트: 2026-03-01

---

## 1. 개념 설명

### IGW란?

Internet Gateway는 VPC와 인터넷 사이의 **논리적 경계점**이다.
VPC 자체는 완전히 격리된 네트워크이고, IGW를 붙여야만 인터넷과 통신할 수 있다.

```
인터넷
   ↓
Internet Gateway   ← VPC에 attach
   ↓
Public Subnet      ← Route Table에 0.0.0.0/0 → igw 경로가 있는 서브넷
   ↓
ALB, NAT Gateway   ← Public IP를 가진 리소스
```

### 핵심 특성

- **VPC당 하나만 존재** — 여러 개 붙일 수 없다
- **수평 확장, 가용성 보장** — AWS가 관리하므로 IGW 자체는 장애나지 않음
- **양방향 통신** — 인터넷 → VPC (inbound), VPC → 인터넷 (outbound) 모두 허용
- **IP 변환(NAT) 없음** — IGW는 Public IP ↔ Private IP 1:1 매핑만 한다. 실제 EC2 내부에서는 Private IP만 보임

### IGW만으로는 인터넷이 안 된다

IGW를 붙이는 것은 **하드웨어 연결**만 한 것이다. 실제 트래픽이 흐르려면:

1. IGW를 VPC에 attach ← `aws_internet_gateway`
2. Route Table에 `0.0.0.0/0 → igw` 경로 추가 ← `aws_route_table`
3. 그 Route Table을 서브넷에 연결 ← `aws_route_table_association`
4. 리소스에 Public IP 할당 ← 서브넷의 `map_public_ip_on_launch = true`
5. Security Group에서 inbound 허용

이 5가지가 모두 있어야 인터넷 통신이 된다.

### Public Subnet과의 관계

"Public Subnet"의 정의는 **IGW로 향하는 Route가 있는 서브넷**이다.
`map_public_ip_on_launch = true`는 서브넷 속성이지 Public Subnet을 만드는 조건이 아니다.

---

## 2. Terraform 구현 참고

→ [핵심 블록 & 모듈 구조](../terraform/core-blocks.md)
→ [aws_internet_gateway 파라미터 설명](../terraform/core-blocks.md#aws_internet_gateway)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 1 — Network Foundation |
| 레이어 | `modules/network/` |

**선행 리소스**: `aws_vpc` — VPC가 먼저 있어야 IGW를 attach할 수 있다

**후행 리소스**:
- `aws_route_table` (public) — IGW ID를 Route에 사용
- `aws_nat_gateway` — IGW가 있어야 NAT GW가 인터넷과 통신 가능 (`depends_on` 필요)

---

## 4. 직접 해볼 것

`modules/network/main.tf`에 `aws_internet_gateway` 리소스를 추가해보자.
- `vpc_id`만 있으면 되는 단순한 리소스다
- 추가 후 `terraform plan`으로 생성될 리소스를 확인

**AWS 공식 문서**:
- [Internet Gateways](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html)
- 검색 키워드: `aws_internet_gateway terraform`, `vpc internet gateway attach`
