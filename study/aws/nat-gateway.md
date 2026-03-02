# NAT Gateway

> 마지막 업데이트: 2026-03-02

---

## 1. 개념 설명

### NAT Gateway란?

Network Address Translation Gateway. Private Subnet의 리소스가 **아웃바운드 인터넷 통신**을 할 수 있게 해주는 장치다.

```
Private EC2 (10.0.11.10)
    ↓ 아웃바운드 패킷
NAT Gateway (Public Subnet에 위치, 고정 Public IP 보유)
    ↓ Private IP → Public IP로 변환 (SNAT)
Internet Gateway
    ↓
인터넷 (8.8.8.8 등)
```

### 왜 필요한가?

Private Subnet의 EC2는 Public IP가 없다. 패키지 설치(`yum install`), 외부 API 호출, S3 접근 등 아웃바운드 통신이 필요할 때 NAT Gateway를 경유한다.

**핵심**: 인터넷 → Private EC2 방향(인바운드)은 NAT를 통해서도 불가능하다. 아웃바운드만 허용된다. 이것이 Private Subnet의 보안 원리다.

### NAT Gateway는 반드시 Public Subnet에 있어야 한다

```
❌ 잘못된 이해: NAT Gateway를 Private Subnet에 두면 됨
✅ 올바른 이해: NAT Gateway는 Public Subnet에 위치해야 함
```

이유: NAT Gateway가 인터넷과 통신하려면 IGW 경로가 있는 서브넷(= Public Subnet)에 있어야 한다.

### Elastic IP (EIP)

NAT Gateway에는 **고정 Public IP**가 필요하다. 이것이 EIP(Elastic IP)다.

- EIP를 먼저 생성하고 NAT Gateway에 할당한다
- Private EC2의 아웃바운드 트래픽은 외부에서 이 EIP로 보이게 된다
- EIP는 인스턴스와 독립적으로 존재 — NAT GW가 삭제되어도 EIP는 남음 (비용 발생)

### AZ별 NAT Gateway — 왜 2개가 필요한가

```
AZ-a                        AZ-c
NAT GW-a                    NAT GW-c
  ↑                           ↑
Private-NAT 서브넷 (a)      Private-NAT 서브넷 (c)
```

AZ-a의 NAT GW가 장애나면?
- AZ-a의 Private EC2 → 아웃바운드 불가
- AZ-c의 NAT를 참조하게 하면 AZ간 트래픽 비용 발생 + 지연 증가

**실무 규칙**: NAT Gateway는 AZ당 1개. Private-NAT Route Table도 AZ별로 분리.

### NAT Gateway vs NAT Instance

| 항목 | NAT Gateway | NAT Instance |
|------|------------|--------------|
| 관리 주체 | AWS 완전 관리 | 직접 EC2 관리 |
| 가용성 | AZ 내 자동 HA | 단일 EC2, 장애 시 수동 대응 |
| 성능 | 최대 100Gbps 자동 확장 | 인스턴스 타입 제한 |
| 비용 | 시간당 + 데이터 전송 요금 | EC2 비용 (소규모에서 저렴할 수 있음) |
| 보안 그룹 | 불가 (NACL만 가능) | 가능 |

실무에서는 NAT Gateway를 사용한다. NAT Instance는 비용 절감이 필요한 소규모 학습/개발 환경에서만 고려한다.

### EIP는 생성과 동시에 연결되지 않는다

`aws_eip` 리소스를 만들면 AWS가 공인 IP를 **내 계정에 예약**한다. 이 시점에서는 아무것도 연결되지 않은 "빈" 상태다.

```
aws_eip 생성 직후:
  IP 주소: 54.180.xxx.xxx  ← AWS가 예약한 공인 IP
  연결 대상: 없음 (unattached)
```

NAT Gateway의 `allocation_id`에 이 EIP ID를 넣을 때 비로소 연결된다.

```
aws_nat_gateway 생성 후:
  allocation_id = aws_eip.nat.id  ← 여기서 연결됨
  이제 NAT GW가 이 IP를 사용해 인터넷 통신
```

**비유**: EIP = 전화번호 예약, NAT GW = 전화기. 전화번호만 예약해두면 아무도 전화 못 받는다.

**비용 주의**: 연결되지 않은 EIP(unattached)는 시간당 요금이 발생한다. NAT GW를 `terraform destroy`할 때 EIP도 반드시 함께 삭제해야 한다.

### NAT GW 개수가 Public Subnet 개수에 종속되는 문제

`for_each = aws_subnet.public` 패턴을 쓰면 **Public Subnet 수 = NAT GW 수**가 고정된다.

```hcl
resource "aws_nat_gateway" "nat" {
  for_each = aws_subnet.public  # Public Subnet 2개 → NAT GW 2개 (강제)
}
```

Public Subnet은 ALB 때문에 Multi-AZ(2개)가 필수지만, dev 환경에서는 NAT GW를 1개로 줄여 비용을 절감하고 싶을 수 있다. 하지만 위 구조에서는 이것이 불가능하다.

**해결 방향**: NAT GW 배치용 서브넷을 별도 변수로 분리한다.

```hcl
# dev: nat_subnet_cidrs에 AZ 1개만 → NAT GW 1개
# prod: nat_subnet_cidrs에 AZ 2개 → NAT GW 2개 (HA)
variable "nat_subnet_cidrs" {
  type = map(string)
}
```

이렇게 하면 Public Subnet 개수와 NAT GW 개수를 독립적으로 제어할 수 있다.

### 실무에서 자주 하는 실수

1. **NAT GW를 Private Subnet에 배치** → 작동 안 됨. 반드시 Public Subnet에
2. **NAT GW 1개를 전체 AZ에서 공유** → 단일 장애점 + AZ간 비용
3. **EIP 삭제 없이 NAT GW 삭제** → EIP가 남아 비용 계속 발생
4. **depends_on 누락** → IGW 없이 NAT GW가 먼저 만들어지려다 실패
5. **EIP를 for_each 없이 1개만 생성** → NAT GW도 1개가 되어 AZ별 HA 불가

---

## 2. Terraform 구현 참고

→ [핵심 블록 & for_each 패턴](../terraform/core-blocks.md)
→ [aws_eip / aws_nat_gateway 파라미터 설명](../terraform/core-blocks.md#aws_eip)
→ [depends_on & lifecycle](../terraform/lifecycle-and-import.md)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 1 — Network Foundation |
| 레이어 | `modules/network/` |

**선행 리소스**:
- `aws_internet_gateway` — `depends_on`으로 명시. EIP가 라우팅 가능하려면 IGW 필요
- `aws_subnet.public` — NAT GW가 위치할 서브넷

**후행 리소스**:
- `aws_route_table` (private-nat) — NAT GW ID를 경로로 사용

---

## 4. 직접 해볼 것

EIP 2개 + NAT GW 2개를 AZ별로 for_each로 만들어보자.
- `aws_eip`의 `domain = "vpc"` 속성 확인
- `aws_nat_gateway`의 `subnet_id`가 Public Subnet을 가리키는지 확인
- `depends_on = [aws_internet_gateway.xxx]` 추가

**AWS 공식 문서**:
- [NAT Gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- 검색 키워드: `aws_nat_gateway terraform per az`, `aws_eip vpc terraform`
