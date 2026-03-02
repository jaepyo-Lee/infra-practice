# modules/network/main.tf
# VPC 모듈의 핵심 리소스만 정의합니다.
# variable, output은 각각 variables.tf, outputs.tf로 분리하는 것이 Terraform 컨벤션입니다.
# 이유: 파일 역할이 명확해져 팀 협업과 유지보수가 쉬워집니다.

resource "aws_vpc" "vpc" {
  cidr_block = var.cidr

  # DNS 옵션 두 가지를 명시적으로 활성화합니다.
  # enable_dns_support   = true: AWS 내부 DNS 서버(169.254.169.253)를 통해 이름 해석을 허용합니다.
  # enable_dns_hostnames = true: 퍼블릭 IP를 가진 EC2 인스턴스에 퍼블릭 DNS 호스트네임을 부여합니다.
  # 이 두 옵션이 활성화되지 않으면 ECS, RDS, ALB 등 서비스가 DNS로 서로를 찾지 못할 수 있습니다.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      # Name 태그는 AWS 콘솔에서 리소스를 식별하는 유일한 수단입니다.
      # "${var.name}-vpc" 패턴으로 환경별 구분이 됩니다 (예: dev-vpc, prod-vpc).
      Name = "study-${var.name}-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  # for_each의 키(each.key)가 AZ 이름, 값(each.value)이 CIDR이다.
  # count와 달리 키 기반이므로 AZ 추가/삭제 시 기존 서브넷이 삭제/재생성되지 않는다.
  for_each                = var.public_subnet_cidrs
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-public-subnet-${each.key}"
    }
  )
}

resource "aws_subnet" "private_nat" {
  # NAT Gateway를 통해 아웃바운드 인터넷만 허용하는 App 서버용 서브넷.
  # map_public_ip_on_launch 생략 = 기본값 false → Public IP 없음.
  for_each          = var.private_nat_subnet_cidrs
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-private-nat-subnet-${each.key}"
    }
  )
}

resource "aws_subnet" "private_full" {
  # 인터넷 완전 차단 서브넷. Route Table에 0.0.0.0/0 경로가 없어 VPC 내부 통신만 가능.
  for_each          = var.private_full_subnet_cidrs
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-private-full-subnet-${each.key}"
    }
  )
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = merge(
    var.tags,
    {
      Name = "${var.name}-internet-gateway"
    }
  )
}

# ✅ for_each = aws_subnet.public 으로 수정
# ❌ 이전 문제: for_each 없이 EIP 1개만 생성했습니다.
# NAT Gateway는 AZ당 1개 필요하고, 각 NAT GW마다 고정 EIP가 1개 필요합니다.
# for_each로 Public Subnet 맵을 순회하면 AZ 수만큼 EIP가 자동 생성됩니다.
# (ap-northeast-2a → eip["ap-northeast-2a"], ap-northeast-2c → eip["ap-northeast-2c"])
resource "aws_eip" "nat" {
  for_each   = aws_subnet.public
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  # depends_on 이유: IGW가 VPC에 attach되기 전에 EIP가 생성되면 라우팅이 불안정합니다.

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-eip-${each.key}"
    }
  )
}

# ✅ for_each + 올바른 subnet_id + allocation_id 로 수정
# ❌ 이전 문제 1: for_each 없이 NAT GW 1개만 생성 → AZ 장애 시 전체 Private 서브넷 아웃바운드 불가
# ❌ 이전 문제 2: subnet_id = aws_subnet.public.id — for_each 리소스는 맵이므로 .id 직접 참조 불가
#                 for_each 리소스는 반드시 aws_subnet.public["az이름"].id 또는 each.value.id 형태로 참조해야 합니다.
# ✅ subnet_id = each.value.id — 현재 순회 중인 AZ의 Public Subnet ID를 참조합니다.
# ✅ allocation_id = aws_eip.nat[each.key].id — 같은 AZ 키로 EIP를 1:1 연결합니다.
resource "aws_nat_gateway" "nat" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  # NAT Gateway는 반드시 Public Subnet(IGW 경로가 있는 서브넷)에 위치해야 합니다.
  # Private Subnet에 두면 NAT GW 자체가 인터넷에 접근할 수 없어 동작하지 않습니다.

  depends_on = [aws_internet_gateway.igw]

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-gateway-${each.key}"
    }
  )
}

# ✅ Public Route Table — IGW로의 경로 (이미 올바르게 구현됨)
# Public Subnet의 모든 아웃바운드 트래픽을 IGW로 보냅니다.
# Public RT는 1개만 필요합니다. IGW는 VPC당 1개이므로 AZ별로 분리할 필요가 없습니다.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
    # 0.0.0.0/0: "local 경로(VPC 내부)에 해당하지 않는 모든 트래픽"을 IGW로 보냅니다.
    # local 경로(10.0.0.0/16 → local)는 AWS가 자동으로 추가하므로 선언 불필요합니다.
  }

  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ✅ Private-NAT Route Table — AZ별 분리 + nat_gateway_id 로 수정
# ❌ 이전 문제 1: gateway_id = aws_internet_gateway.igw.id 로 잘못 설정
#                 → Private Subnet 트래픽이 NAT GW가 아닌 IGW로 직접 가게 됨
#                 → IGW는 Public IP가 없는 Private EC2 패킷을 라우팅할 수 없어 실질적으로 인터넷 차단됨
# ❌ 이전 문제 2: for_each 없이 RT 1개만 생성 → 모든 AZ가 단일 NAT GW 의존 (단일 장애점)
# ✅ for_each로 AZ별 RT 생성 → 각 AZ가 자기 AZ의 NAT GW를 참조
# 이유: AZ-a의 NAT GW가 장애나도 AZ-c는 자체 NAT GW로 계속 동작합니다.
resource "aws_route_table" "private_nat" {
  for_each = aws_subnet.private_nat
  vpc_id   = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[each.key].id
    # each.key는 AZ 이름 — 같은 AZ의 NAT GW를 참조하여 AZ 내부 트래픽 흐름을 유지합니다.
    # AZ간 트래픽은 추가 비용이 발생하므로 반드시 같은 AZ의 NAT GW를 참조해야 합니다.
  }

  tags = merge(var.tags, { Name = "${var.name}-private-nat-rt-${each.key}" })
}

resource "aws_route_table_association" "private_nat" {
  for_each       = aws_subnet.private_nat
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_nat[each.key].id
  # each.key로 같은 AZ의 private_nat RT와 연결합니다.
}

# ✅ Private-Full Route Table — 추가
# ❌ 이전에 없었던 리소스입니다.
# route 블록이 없으므로 0.0.0.0/0 경로가 존재하지 않습니다.
# → VPC 내부(local) 통신만 가능, 인터넷 완전 차단.
# RDS, ElastiCache 같은 DB 레이어가 이 서브넷에 위치합니다.
# Private-Full은 모든 AZ가 동일한 라우팅 규칙(인터넷 차단)을 사용하므로 RT 1개로 충분합니다.
resource "aws_route_table" "private_full" {
  vpc_id = aws_vpc.vpc.id
  # route 블록 없음 = 인터넷 경로 없음
  # AWS가 자동으로 추가하는 local 경로(VPC CIDR → local)만 존재합니다.

  tags = merge(var.tags, { Name = "${var.name}-private-full-rt" })
}

resource "aws_route_table_association" "private_full" {
  for_each       = aws_subnet.private_full
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_full.id
  # private_full RT는 1개이므로 [each.key] 인덱스 없이 직접 참조합니다.
}