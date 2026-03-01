# Subnet

> 마지막 업데이트: 2026-03-01

---

## 핵심 개념

### VPC와의 관계

Subnet은 VPC IP 공간의 일부를 잘라낸 구획이다.
- VPC `10.0.0.0/16` 안에서 `10.0.1.0/24`를 잘라내면 그게 서브넷 하나
- 리소스(EC2, RDS 등)는 반드시 특정 서브넷 안에 배치된다
- 서브넷은 하나의 AZ에만 속한다 (AZ 장애 대비 → 같은 역할의 서브넷을 여러 AZ에)

### Public vs Private 구분 기준

| 구분 | map_public_ip_on_launch | Route Table |
|------|------------------------|-------------|
| Public | true | 0.0.0.0/0 → IGW |
| Private | false (생략 가능) | 0.0.0.0/0 → NAT (or 없음) |

Public IP 할당 여부와 Route Table이 함께 결정한다.
`map_public_ip_on_launch = true`만으로는 인터넷이 안 된다. Route Table에 IGW 경로가 있어야 한다.

### AWS가 예약하는 5개 IP

`/24` 서브넷(256개)에서 실제 사용 가능한 IP는 **251개**다.

```
10.0.1.0   → 네트워크 주소
10.0.1.1   → AWS VPC 라우터
10.0.1.2   → AWS DNS 서버
10.0.1.3   → AWS 미래 예약
10.0.1.255 → 브로드캐스트
```

---

## Terraform 구현 예시

### count를 이용한 반복 생성 패턴

서브넷 종류가 3가지(Public, App, DB)이고 각각 2개 AZ에 배치한다면,
리소스 블록 3개 + count = 서브넷 6개가 된다.

```hcl
# Public Subnet — ALB, NAT Gateway가 위치
# map_public_ip_on_launch = true → 이 서브넷에 올라오는 리소스에 Public IP 자동 할당
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)  # 리스트 길이(2)만큼 반복

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]  # [0] = 첫 번째, [1] = 두 번째
  availability_zone = var.azs[count.index]                  # cidr과 az의 인덱스가 같이 증가

  map_public_ip_on_launch = true  # Public Subnet만 true

  tags = merge(
    var.tags,
    {
      # count.index + 1 → 1부터 시작하는 번호 (0부터 시작하면 어색함)
      Name = "${var.name}-public-subnet-${count.index + 1}"
    }
  )
}

# Private App Subnet — EC2 App Server가 위치
# 인터넷 직접 접근 불가. NAT를 통해 아웃바운드만 가능.
resource "aws_subnet" "private_app" {
  count = length(var.private_app_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # map_public_ip_on_launch 생략 = 기본값 false → Public IP 없음

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-private-app-subnet-${count.index + 1}"
    }
  )
}

# Private DB Subnet — RDS, ElastiCache가 위치
# Route Table에 0.0.0.0/0 경로 없음 → 완전 격리
resource "aws_subnet" "private_db" {
  count = length(var.private_db_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-private-db-subnet-${count.index + 1}"
    }
  )
}
```

### count.index 동작 방식

```
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
azs                 = ["ap-northeast-2a", "ap-northeast-2b"]

count = 2일 때:

  count.index = 0 → cidr: 10.0.1.0/24, az: ap-northeast-2a
  count.index = 1 → cidr: 10.0.2.0/24, az: ap-northeast-2b
```

cidr 리스트와 az 리스트의 인덱스가 대응되도록 순서를 맞춰서 변수에 넣어줘야 한다.

### 생성되는 리소스 이름 (Terraform State 기준)

```
aws_subnet.public[0]      → 10.0.1.0/24, ap-northeast-2a
aws_subnet.public[1]      → 10.0.2.0/24, ap-northeast-2b
aws_subnet.private_app[0] → 10.0.11.0/24, ap-northeast-2a
aws_subnet.private_app[1] → 10.0.12.0/24, ap-northeast-2b
aws_subnet.private_db[0]  → 10.0.21.0/24, ap-northeast-2a
aws_subnet.private_db[1]  → 10.0.22.0/24, ap-northeast-2b
```

### outputs.tf에 추가할 것

다른 모듈(security_groups, alb, rds 등)이 subnet ID를 참조할 수 있도록 노출해야 한다.

```hcl
output "public_subnet_ids" {
  value       = aws_subnet.public[*].id  # [*] = 모든 인덱스의 id를 리스트로
  description = "Public Subnet ID 목록. ALB, NAT Gateway 배치에 사용"
}

output "private_app_subnet_ids" {
  value       = aws_subnet.private_app[*].id
  description = "Private App Subnet ID 목록. EC2 Auto Scaling Group 배치에 사용"
}

output "private_db_subnet_ids" {
  value       = aws_subnet.private_db[*].id
  description = "Private DB Subnet ID 목록. RDS Subnet Group, ElastiCache Subnet Group에 사용"
}
```

---

## 실무 주의사항

1. **cidr과 az 리스트 길이를 반드시 맞춰야 한다** — 다르면 index out of range 오류
2. **서브넷 CIDR은 생성 후 변경 불가** — 잘못 설계하면 삭제 후 재생성
3. **AZ는 최소 2개** — 하나면 그 AZ 장애 시 전체 서비스 중단
