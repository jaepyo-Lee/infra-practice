# VPC (Virtual Private Cloud)

> 마지막 업데이트: 2026-03-01 (CIDR 계층 구조 — IP 할당 vs 통신 범위 추가)

---

## 1. 개념 설명 (AWS 관점)

### VPC란?

VPC(Virtual Private Cloud)는 AWS 내에 논리적으로 격리된 가상 네트워크다. AWS 계정을 만들면 클라우드라는 거대한 공용 네트워크 위에 올라가는데, VPC는 그 안에 **내 전용 네트워크 구역**을 만드는 것이다.

**왜 필요한가?**
- AWS 리소스(EC2, RDS 등)는 반드시 어떤 네트워크 안에 속해야 한다
- 인터넷에서 직접 닿으면 안 되는 리소스(DB 등)를 격리하기 위해
- 온프레미스 데이터센터와 VPN/Direct Connect로 연결하기 위한 기반

### 내부 동작 방식

VPC는 **소프트웨어로 구현된 네트워크 장비 집합**이다. 물리 스위치/라우터가 없고, AWS가 SDN(Software Defined Networking)으로 구현한다.

```
인터넷
    ↓
Internet Gateway (IGW)            ← VPC와 인터넷의 경계점
    ↓
Public Subnet (10.0.1.0/24)       ← IGW로 라우팅 가능한 서브넷
  └── ALB, NAT Gateway
    ↓
Private App Subnet (10.0.11.0/24) ← 인터넷 직접 접근 불가
  └── EC2 (App Server)
    ↓
Private DB Subnet (10.0.21.0/24)  ← 더 깊은 격리
  └── RDS, ElastiCache
```

### 핵심 구성 요소

| 구성요소 | 역할 |
|---------|------|
| **CIDR Block** | VPC 전체 IP 범위 정의 (예: 10.0.0.0/16 = 65,536개 IP) — 아래 CIDR 섹션 참고 |
| **Subnet** | VPC를 작은 구역으로 나눔. AZ에 종속됨 |
| **Route Table** | 서브넷별 트래픽 경로 결정 |
| **IGW** | VPC↔인터넷 연결. Public Subnet에서 사용 |
| **NAT Gateway** | Private Subnet에서 아웃바운드 인터넷 허용 |
| **Security Group** | 인스턴스 수준 방화벽 (Stateful) |
| **NACL** | 서브넷 수준 방화벽 (Stateless) |

### Subnet — AZ 설계가 중요한 이유

서브넷은 반드시 하나의 AZ에 속한다. 고가용성을 위해 **같은 역할의 서브넷을 여러 AZ에 복수로 만든다**.

```
ap-northeast-2a                    ap-northeast-2b
  Public  10.0.1.0/24               Public  10.0.2.0/24
  App     10.0.11.0/24              App     10.0.12.0/24
  DB      10.0.21.0/24              DB      10.0.22.0/24
```

AZ-a가 장애나면 AZ-b로 트래픽이 자동 전환된다. 이것이 Multi-AZ의 핵심이다.

### Route Table 동작 원리

패킷이 서브넷을 떠날 때 Route Table을 참조해 어디로 보낼지 결정한다.

**Public Subnet Route Table** (인터넷 접근 허용):
```
Destination     Target
10.0.0.0/16     local     ← VPC 내부 통신
0.0.0.0/0       igw-xxx   ← 나머지는 인터넷으로
```

**Private Subnet Route Table** (아웃바운드만):
```
Destination     Target
10.0.0.0/16     local
0.0.0.0/0       nat-xxx   ← NAT를 통해 아웃바운드만 가능
```

**DB Subnet Route Table** (완전 격리):
```
Destination     Target
10.0.0.0/16     local     ← VPC 내부만. 인터넷 없음.
```

### NAT Gateway vs NAT Instance

| 항목 | NAT Gateway | NAT Instance |
|------|------------|--------------|
| 관리 | AWS 완전 관리 | 직접 EC2 관리 |
| 가용성 | AZ 수준 자동 고가용성 | 직접 구성 필요 |
| 비용 | 시간당 + 데이터 요금 | EC2 비용 |
| 대역폭 | 최대 100 Gbps | 인스턴스 타입 제한 |

실무에서는 NAT Gateway. **단, AZ당 하나씩** 만들어야 AZ 장애 시에도 Private Subnet이 아웃바운드 통신이 된다.

### VPC DNS 옵션 — enable_dns_support vs enable_dns_hostnames

두 옵션은 역할이 다르며, **둘 다 켜야 의미가 있다.**

#### `enable_dns_support = true`

AWS가 VPC 안에 **내부 DNS 서버를 활성화**한다는 뜻이다. "DNS 서버 자체를 켜는 스위치"다.

이 DNS 서버의 주소는 항상:
- `VPC CIDR의 두 번째 IP` (예: VPC가 `10.0.0.0/16`이면 → `10.0.0.2`)
- 또는 링크 로컬 주소 `169.254.169.253`

이 옵션이 꺼져 있으면 VPC 내부 인스턴스가 DNS 쿼리 자체를 보낼 수 없다.

#### `enable_dns_hostnames = true`

퍼블릭 IP를 가진 EC2 인스턴스에 **DNS 이름을 자동 부여**한다.

켜지면 인스턴스에 이런 이름이 생긴다:
```
ec2-13-125-100-200.ap-northeast-2.compute.amazonaws.com
```

꺼져 있으면 퍼블릭 IP는 있지만 DNS 이름이 없다.

#### 조합별 결과

| support | hostnames | 결과 |
|---------|-----------|------|
| false | true | DNS 서버 자체가 없으니 hostnames 무의미 |
| true | false | DNS 서버는 있지만 인스턴스 이름이 부여 안 됨 |
| true | true | DNS 서버도 있고, 이름도 생성됨 ✅ |

#### 왜 실무에서 중요한가

RDS, ALB, EFS, ECS 등 **AWS 관리형 서비스는 IP가 아닌 DNS 이름으로 접근**한다.

```
# RDS 엔드포인트 예시
mydb.xxxxxx.ap-northeast-2.rds.amazonaws.com
```

EC2에서 이 이름을 해석하려면 `enable_dns_support = true`가 반드시 필요하다.
이 옵션이 꺼져 있으면 같은 VPC 안에서도 RDS 연결 자체가 불가능하다.

> AWS 기본값은 둘 다 `true`지만, Terraform에서는 명시적으로 쓰는 게 Best Practice다.
> 코드를 읽을 때 의도가 명확해지고, 다른 사람이 변경하다 실수로 끄는 것을 방지한다.

---

### CIDR 표기법 이해

CIDR(Classless Inter-Domain Routing)은 IP 주소 범위를 표현하는 방법이다.

```
10.0.0.0/16
└─────┘ └┘
 시작 IP  고정 비트 수
```

IP 주소는 4개의 숫자(각 8비트)로 구성된다:
```
10  .  0  .  0  .  0
1번칸  2번칸  3번칸  4번칸  (각 칸 = 8비트 = 0~255)
```

`/숫자`는 앞에서 몇 비트를 고정하느냐를 의미한다:

| CIDR | 고정 범위 | 사용 가능 IP 수 | 용도 |
|------|---------|--------------|------|
| `/8` | 1번칸 고정 (10.x.x.x) | 16,777,216개 | 너무 큼 |
| `/16` | 1,2번칸 고정 (10.0.x.x) | 65,536개 | **VPC 권장** |
| `/24` | 1,2,3번칸 고정 (10.0.0.x) | 256개 | **Subnet 권장** |

#### 왜 VPC는 /16, Subnet은 /24인가?

```
VPC = 10.0.0.0/16  (토지 전체)
  → 10.0.0.0 ~ 10.0.255.255 소유
  → /24짜리 서브넷을 254개까지 만들 수 있음

서브넷 = 10.0.1.0/24  (토지를 나눈 구획)
  → 10.0.1.0 ~ 10.0.1.255 (256개 IP)
```

VPC가 /24이면 서브넷 1개로 꽉 차서 추가 분할 불가. 나중에 VPC CIDR은 변경 불가능하므로 처음부터 /16으로 여유 있게 설계해야 한다.

#### 이 프로젝트의 CIDR 설계

```
VPC: 10.0.0.0/16

Public Subnet:      10.0.1.0/24 (AZ-a), 10.0.2.0/24 (AZ-b)
Private App Subnet: 10.0.11.0/24 (AZ-a), 10.0.12.0/24 (AZ-b)
Private DB Subnet:  10.0.21.0/24 (AZ-a), 10.0.22.0/24 (AZ-b)
```

3번째 칸(11, 12, 21, 22...)으로 역할을 구분하고, AZ는 마지막 숫자로 구분한다.

#### 사설 IP 대역 (AWS VPC에서만 사용 가능한 범위)

| 대역 | 범위 |
|------|------|
| `10.0.0.0/8` | 10.x.x.x 전체 |
| `172.16.0.0/12` | 172.16.x.x ~ 172.31.x.x |
| `192.168.0.0/16` | 192.168.x.x 전체 |

이 세 대역 외의 IP는 VPC CIDR로 사용할 수 없다.

#### 왜 Public IP를 안 쓰고 사설 IP를 쓰는가?

**이유 1: Public IPv4는 부족하고 비싸다**

IPv4 주소는 전 세계 총 43억 개뿐이다. 2011년에 이미 IANA의 IPv4 풀이 소진되었고, 현재는 반납된 IP를 재분배하거나 구매해야 한다. AWS도 2024년부터 Public IPv4 주소에 시간당 $0.005를 과금한다.

**이유 2: 보안 — 인터넷에 노출될 필요가 없는 리소스에는 주지 않는다**

DB 서버, App 서버는 인터넷에서 직접 접근되면 안 된다. Private IP만 가진 리소스는 인터넷 라우터가 경로를 모르기 때문에 패킷 자체가 도달하지 못한다. "접근 필요가 없으면 애초에 노출하지 않는다"가 VPC 설계 원칙이다.

**이유 3: 사설 IP 대역은 중복 사용 가능하다**

RFC 1918에서 정의한 사설 IP 대역은 인터넷 라우터가 라우팅하지 않기로 전 세계적으로 합의된 대역이다. 덕분에 모든 회사가 `10.0.0.0/16`을 각자 사용해도 인터넷에서 충돌하지 않는다.

```
그럼 외부 통신이 필요할 때는?
  ├── Public IP 필요 (ALB, 일부 EC2): Elastic IP 또는 자동 Public IP 할당
  ├── 아웃바운드만 필요 (App Server): NAT Gateway 경유
  └── 완전 격리 (DB): 아무것도 없음 — VPC 내부 통신만 허용
```

---

### 실무에서 자주 하는 실수

1. **NAT Gateway를 한 AZ에만** → 다른 AZ의 Private Subnet은 NAT가 죽으면 아웃바운드 불가
2. **CIDR를 너무 작게** → 나중에 Subnet 추가 불가. VPC CIDR는 변경 안 됨
3. **모든 Subnet을 Public으로** → 보안 설계 실패
4. **Route Table을 Subnet에 연결 안 함** → 기본 Route Table에 붙어버려 의도와 다르게 동작
5. **VPC Endpoint 미사용** → S3/DynamoDB 접근이 인터넷을 경유해 NAT 비용 발생

---

### VPC Flow Logs — 개념만 (이 프로젝트에서는 미구현)

> 실제 운영 서비스나 보안/컴플라이언스 요건이 있는 환경이 아니면 비용 대비 실익이 낮다.
> 이 프로젝트에서는 개념만 이해하고 넘어간다.

#### Flow Logs란?

VPC 내 **네트워크 인터페이스(ENI)를 통과하는 IP 트래픽의 메타데이터**를 기록하는 서비스다.
패킷 내용(payload)은 캡처하지 않는다 — 출발지 IP, 목적지 IP, 포트, 프로토콜, 허용/차단 여부, 바이트 수 등만 기록한다.

```
기록되는 정보 예시:
  2 123456789012 eni-xxx 10.0.1.5 10.0.11.20 443 52341 6 10 840 ACCEPT OK
  │  계정ID       ENI     출발지IP   목적지IP   dst  src  TCP 패킷 바이트 결과
```

#### 로그 저장 위치

| 저장 대상 | 특징 |
|----------|------|
| CloudWatch Logs | 실시간 분석, Insights 쿼리 가능. 비용이 더 비쌈 |
| S3 | 장기 보관, Athena로 쿼리. 저장 비용이 저렴 |

#### 캡처 범위

- VPC 전체, 특정 서브넷, 특정 ENI(인스턴스) 단위로 선택 가능
- Accept(허용된 트래픽), Reject(차단된 트래픽), All 중 선택

#### 언제 필요한가?

- **보안 사고 대응**: 누가 어디서 접근을 시도했는지 역추적
- **컴플라이언스**: PCI DSS, HIPAA 등 규정에서 네트워크 감사 로그를 요구
- **트래픽 분석**: 예상치 못한 대역폭 소비 원인 파악
- **Security Group 규칙 검증**: 차단된 요청이 있는지 확인

#### 왜 이 프로젝트에서 건너뛰는가?

Flow Logs는 트래픽 양에 비례해 과금된다 (CloudWatch 수집 $0.50/GB, S3 저장 $0.023/GB).
실 운영 서비스처럼 트래픽이 없는 학습 환경에서도 인프라를 켜두면 idle 로그가 쌓인다.
대규모 기업의 프로덕션 환경이 아니라면 비용 대비 실익이 낮다.

---

## 2. Terraform 구현 참고

VPC/Subnet/IGW/NAT/Route Table의 Terraform 리소스 구현은 아래를 참고한다:
- [핵심 블록 & for_each 패턴](../terraform/core-blocks.md)
- [모듈 구조 컨벤션](../terraform/module-structure.md)
- [lifecycle & import (State 관리)](../terraform/lifecycle-and-import.md)

---

## 3. 이 프로젝트에서의 위치

| 항목 | 내용 |
|------|------|
| Phase | Phase 1 — Network Foundation |
| 레이어 | `modules/network/` |

**선행 리소스**: 없음. VPC가 가장 먼저 만들어진다.

**후행 리소스 (모두 VPC에 의존)**:
- `aws_security_group` → `vpc_id` 참조
- `aws_subnet` → `vpc_id` 참조
- `aws_lb` (ALB) → `subnet_ids` 참조
- `aws_db_subnet_group` → `subnet_ids` 참조
- `aws_elasticache_subnet_group` → `subnet_ids` 참조

VPC의 output은 프로젝트 전체에서 가장 많이 참조되는 값이다 — `vpc_id`, `public_subnet_ids`, `private_app_subnet_ids`, `private_db_subnet_ids`.

---

## 4. 직접 해볼 것

**지금 해볼 실습**: 이 프로젝트의 3-Tier 아키텍처에서 VPC 설계도를 직접 그려보자.

- AZ를 몇 개 쓸지 (최소 2개)
- Public/Private/DB 서브넷 각각의 역할과 통신 방향
- NAT Gateway 위치와 개수 (AZ마다 1개가 Best Practice인 이유)

**AWS 공식 문서**:
- [VPC and subnets](https://docs.aws.amazon.com/vpc/latest/userguide/configure-your-vpc.html)
- [NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- 검색 키워드: `aws vpc multi-az design`, `nat gateway high availability`
