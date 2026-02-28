# VPC (Virtual Private Cloud)

> 마지막 업데이트: 2026-02-28 (DNS 옵션 상세 추가)

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
| **CIDR Block** | VPC 전체 IP 범위 정의 (예: 10.0.0.0/16 = 65,536개 IP) |
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

### 실무에서 자주 하는 실수

1. **NAT Gateway를 한 AZ에만** → 다른 AZ의 Private Subnet은 NAT가 죽으면 아웃바운드 불가
2. **CIDR를 너무 작게** → 나중에 Subnet 추가 불가. VPC CIDR는 변경 안 됨
3. **모든 Subnet을 Public으로** → 보안 설계 실패
4. **Route Table을 Subnet에 연결 안 함** → 기본 Route Table에 붙어버려 의도와 다르게 동작
5. **VPC Endpoint 미사용** → S3/DynamoDB 접근이 인터넷을 경유해 NAT 비용 발생

---

## 2. Terraform 구현

### 필요한 리소스 목록

```
aws_vpc
aws_subnet                    × 6 (Public 2, App 2, DB 2)
aws_internet_gateway
aws_nat_gateway               × 2 (AZ별)
aws_eip                       × 2 (NAT Gateway용)
aws_route_table               × 4 (Public 1, Private AZ-a 1, Private AZ-b 1, DB 1)
aws_route_table_association   × 6 (각 Subnet에 Route Table 연결)
```

### aws_vpc — 핵심 argument

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # DNS 설정 — 둘 다 true여야 EC2에서 도메인명으로 통신 가능
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}
```

### aws_subnet

```hcl
# Public Subnet — AZ-a
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"

  # true면 인스턴스 생성 시 Public IP 자동 할당
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-a" }
}
```

### Internet Gateway

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "main-igw" }
}
```

### NAT Gateway (AZ별)

```hcl
# EIP는 NAT Gateway에 붙는 고정 Public IP
resource "aws_eip" "nat_a" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]  # IGW가 먼저 있어야 함
}

resource "aws_nat_gateway" "a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id   # 반드시 Public Subnet에!

  tags = { Name = "nat-gw-a" }
}
```

### Route Table

```hcl
# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "public-rt" }
}

# Private Route Table (AZ-a) — NAT 경유
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.a.id
  }

  tags = { Name = "private-rt-a" }
}

# Subnet과 Route Table 연결
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
```

### 리소스 간 참조 관계

```
aws_vpc
  ├── aws_subnet (vpc_id)
  │     └── aws_route_table_association (subnet_id)
  ├── aws_internet_gateway (vpc_id)
  │     └── aws_route_table.public (gateway_id)
  └── aws_route_table (vpc_id)

aws_eip
  └── aws_nat_gateway (allocation_id)
        └── aws_route_table.private (nat_gateway_id)

aws_subnet.public_a
  └── aws_nat_gateway (subnet_id)  ← NAT는 Public Subnet에 위치
```

### 자주 쓰이는 패턴 — count 반복

```hcl
variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
```

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

VPC의 output은 프로젝트 전체에서 가장 많이 참조되는 값이다:

```hcl
# modules/network/outputs.tf 예시
output "vpc_id"                  { value = aws_vpc.main.id }
output "public_subnet_ids"       { value = [aws_subnet.public_a.id, aws_subnet.public_b.id] }
output "private_app_subnet_ids"  { value = [aws_subnet.app_a.id, aws_subnet.app_b.id] }
output "private_db_subnet_ids"   { value = [aws_subnet.db_a.id, aws_subnet.db_b.id] }
```

---

## 4. 직접 해볼 것

**지금 해볼 실습**: `modules/network/`의 input/output을 설계해보자.

`variables.tf`에서 받아야 할 값 목록을 직접 생각해보자:
- VPC CIDR, 각 Subnet CIDR, AZ 목록, 환경 이름(env) 등

어떤 값을 변수로 받고 어떤 값을 하드코딩할지 결정하는 것이 모듈 설계의 핵심이다.

**참고 문서**:
- [aws_vpc | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)
- [aws_nat_gateway | Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway)
- 검색 키워드: `terraform vpc multi-az nat gateway per az`, `aws vpc route table association terraform`
