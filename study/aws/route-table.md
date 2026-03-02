# Route Table

> 마지막 업데이트: 2026-03-01

---

## 1. 개념 설명

### Route Table이란?

서브넷을 떠나는 패킷이 **어디로 가야 하는지** 결정하는 라우팅 규칙표다.
네트워크 공학의 라우팅 테이블과 동일한 개념이다.

```
패킷 목적지: 8.8.8.8 (구글 DNS)

Route Table 조회:
  10.0.0.0/16 → local   ← VPC 내부? NO
  0.0.0.0/0   → igw     ← 나머지는 IGW로 → 인터넷 ✅
```

### 경로 매칭 규칙: 가장 구체적인 것이 우선

```
목적지: 10.0.5.100

Route Table:
  10.0.0.0/16 → local    ← /16이 매칭
  0.0.0.0/0   → igw      ← 모든 것이 매칭

결과: 10.0.0.0/16이 더 구체적이므로 → local 선택
```

`local` 경로는 AWS가 자동으로 추가한다. VPC 내부 통신은 항상 이 경로를 탄다.

### 이 프로젝트에서 필요한 Route Table 3종류

| Route Table | 붙일 서브넷 | 0.0.0.0/0 경로 | 의미 |
|-------------|-----------|--------------|------|
| public-rt | Public × 2 | → IGW | 인터넷 양방향 |
| private-nat-rt | Private-NAT × 2 | → NAT GW | 아웃바운드만 |
| private-full-rt | Private-Full × 2 | 없음 | VPC 내부만 |

### Public RT가 1개인 이유

Public Subnet이 2개(AZ-a, AZ-c)여도 Public Route Table은 1개만 필요하다.

이유: **IGW는 VPC당 1개만 생성 가능**하다. Public Subnet들의 아웃바운드 경로는 모두 동일하게 `0.0.0.0/0 → IGW`이므로, 같은 Route Table을 공유해도 된다.

```
Public Subnet (AZ-a) ─┐
                       ├── Public RT (0.0.0.0/0 → IGW) ── IGW (VPC당 1개)
Public Subnet (AZ-c) ─┘
```

반면 Private-NAT RT는 AZ별로 2개가 필요하다. NAT GW는 AZ당 1개씩 다르기 때문에 AZ마다 경로가 달라진다.

```
Private-NAT (AZ-a) ── Private-NAT RT-a (→ NAT GW-a)
Private-NAT (AZ-c) ── Private-NAT RT-c (→ NAT GW-c)
```

한 줄 요약: **경로의 목적지가 같으면 RT 공유 가능. 다르면 분리 필요.**

### Route Table Association

Route Table을 만들어도 서브넷에 **명시적으로 연결**해야 적용된다.
연결하지 않으면 서브넷은 VPC의 Default Route Table을 사용한다.

```
aws_route_table "public"
        ↓ (aws_route_table_association)
aws_subnet.public["ap-northeast-2a"]
aws_subnet.public["ap-northeast-2c"]
```

### Default Route Table의 함정

VPC 생성 시 Default Route Table이 자동 생성된다.
명시적으로 Route Table을 연결하지 않은 서브넷은 이 Default Route Table에 붙는다.
Default Route Table은 `local` 경로만 있어 인터넷 접근이 안 되지만, **실수로 0.0.0.0/0 → igw를 추가하면 모든 서브넷이 Public이 되는 보안 사고 발생**.

Best Practice: 모든 서브넷에 명시적으로 Route Table을 연결하고, Default Route Table은 건드리지 않는다.

### 인바운드 vs 아웃바운드 — Route Table의 역할 범위

Route Table은 **서브넷을 떠나는(outbound) 패킷의 경로**만 결정한다. 인바운드는 Route Table의 대상이 아니다.

**왜 인바운드는 Route Table 설정이 필요 없는가?**

모든 TCP 패킷에는 출발지 IP/포트 + 목적지 IP/포트 4가지 정보가 담겨 있다(4-tuple).

```
클라이언트 → EC2 요청 패킷:
  출발지 IP   : 220.10.5.3
  출발지 Port : 54321   ← 클라이언트 OS가 임시 배정한 Ephemeral Port
  목적지 IP   : 10.0.1.100 (ALB)
  목적지 Port : 443
```

IGW는 이미 목적지 IP를 알고 있다. 클라이언트가 ALB의 Public IP로 요청을 보내면, IGW는 그 IP를 VPC 내부 Private IP로 1:1 매핑해서 직접 해당 서브넷으로 전달한다. "어느 서브넷으로 보낼까"를 별도로 결정할 필요가 없다 — 목적지 IP 자체가 이미 그 서브넷 안에 있기 때문이다.

**응답 패킷(Reply)은 아웃바운드로 처리된다.** EC2가 응답할 때는 패킷의 출발지/목적지를 뒤집으면 된다 — 요청 패킷의 출발지(220.10.5.3:54321)가 응답의 목적지가 된다. Route Table이 이 응답 패킷의 경로를 결정한다.

```
EC2 → 클라이언트 응답 패킷:
  출발지 IP   : 10.0.1.100 (ALB)
  출발지 Port : 443
  목적지 IP   : 220.10.5.3   ← 요청 패킷의 출발지
  목적지 Port : 54321         ← Ephemeral Port로 되돌아감
```

| 제어 목적 | 담당 레이어 |
|---------|-----------|
| 인바운드 트래픽 허용/차단 | Security Group (포트/IP 기반) |
| 서브넷 레벨 인바운드 차단 | NACL |
| 패킷 경로 결정 | Route Table (아웃바운드 전용) |

### Stateful vs Stateless — Security Group과 NACL의 차이

"연결 상태를 기억하는가"의 차이다. 이것이 SG와 NACL의 핵심 구분이다.

**Security Group (Stateful)**

연결 테이블을 유지한다. 인바운드 요청이 허용되면, 그 연결의 응답 패킷은 **아웃바운드 규칙 없이 자동 허용**된다.

```
SG Inbound:  0.0.0.0/0 → Port 80 허용  ✅
SG Outbound: 규칙 없어도 응답 자동 허용  ✅
```

**NACL (Stateless)**

패킷 하나하나를 독립적으로 판단한다. 연결 상태를 모르므로 인바운드와 아웃바운드 규칙을 **각각 따로** 설정해야 한다.

```
NACL Inbound:  0.0.0.0/0 → Port 80 허용  ✅
NACL Outbound: Ephemeral Port 범위(1024-65535) 허용도 필요  ✅
               (없으면 응답 패킷이 차단됨)
```

**Ephemeral Port (임시 포트)**: 클라이언트 OS가 요청 시 임시로 배정하는 포트(1024-65535). 응답 패킷의 목적지 포트가 이 범위다. NACL에서 아웃바운드 이 범위를 열어두지 않으면 응답이 차단된다.

### NAT Gateway와 Route Table의 관계

Private-NAT 서브넷은 AZ별로 **다른 NAT Gateway**를 사용해야 한다.

```
ap-northeast-2a의 Private-NAT 서브넷 → AZ-a의 NAT GW
ap-northeast-2c의 Private-NAT 서브넷 → AZ-c의 NAT GW
```

왜 AZ별로 다른 NAT GW인가? AZ-a의 NAT GW가 장애나면 AZ-a의 Private EC2도 아웃바운드 불가. 다른 AZ의 NAT를 참조하면 AZ간 데이터 전송 비용도 발생.

따라서 private-nat Route Table도 **AZ별로 2개** 필요하다.

---

## 2. Terraform 구현 참고

→ [핵심 블록 & for_each 패턴](../terraform/core-blocks.md)
→ [aws_route_table / aws_route_table_association 파라미터 설명](../terraform/core-blocks.md#aws_route_table)
→ [모듈 구조 컨벤션](../terraform/module-structure.md)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 1 — Network Foundation |
| 레이어 | `modules/network/` |

**선행 리소스**:
- `aws_vpc` — Route Table은 VPC 안에 존재
- `aws_internet_gateway` — public-rt의 경로로 사용
- `aws_nat_gateway` — private-nat-rt의 경로로 사용

**후행 리소스**:
- 모든 리소스 — 통신이 가능해야 배포/접근 가능

---

## 4. 직접 해볼 것

Public Route Table 하나를 먼저 만들고, Public 서브넷 2개에 연결해보자.
- Route Table 생성 → IGW 경로 추가 → Association 2개
- `terraform plan`에서 4개 리소스(1 route_table + 2 association + 1 route)가 나오면 정상

**AWS 공식 문서**:
- [Route Tables](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html)
- 검색 키워드: `aws_route_table terraform`, `aws_route_table_association for_each`
