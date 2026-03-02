# modules/network/outputs.tf
# 이 모듈이 외부로 노출하는 값을 선언합니다.
# 다른 모듈이 `module.network.vpc_id` 형태로 참조합니다.
# 이유: outputs.tf가 없으면 모듈 간 참조가 불가능하여 각 모듈이 독립적으로 동작할 수 없습니다.

output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "생성된 VPC의 ID. 서브넷, 보안그룹, NAT Gateway, IGW 등 대부분의 네트워크 리소스에서 필수로 참조합니다."
  # 예: module.security_groups에서 vpc_id = module.network.vpc_id 형태로 사용됩니다.
}

output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "VPC의 CIDR 블록. 서브넷 CIDR 계획 또는 보안그룹 내부 트래픽 허용 규칙 정의 시 참조합니다."
  # 예: aws_security_group의 ingress cidr_blocks = [module.network.vpc_cidr_block]
}

output "public_subnet_ids" {
  value       = values(aws_subnet.public)[*].id
  description = "Public Subnet ID 목록. ALB, NAT Gateway 배치에 사용. values()로 맵에서 리스트로 변환."
  # values()가 필요한 이유: for_each 리소스는 맵(map) 형태로 저장됩니다.
  # [*].id 스플랫 연산자는 리스트에서만 동작하므로 values()로 먼저 리스트로 변환해야 합니다.
}

output "private_nat_subnet_ids" {
  value       = values(aws_subnet.private_nat)[*].id
  description = "Private NAT Subnet ID 목록. EC2 Auto Scaling Group 배치에 사용."
}

output "private_full_subnet_ids" {
  value       = values(aws_subnet.private_full)[*].id
  description = "Private Full Subnet ID 목록. RDS Subnet Group, ElastiCache Subnet Group에 사용."
}

# ✅ nat_gateway_ids 추가
# ❌ 이전에 없었던 output입니다.
# 후속 레이어(2-security 이후)에서 VPN, Transit Gateway, 또는 특정 보안 도구가
# NAT GW의 고정 IP(EIP)를 화이트리스트에 추가할 때 이 output을 참조합니다.
# { AZ => NAT GW ID } 맵 형태로 노출해 호출자가 AZ별로 참조할 수 있게 합니다.
output "nat_gateway_ids" {
  value       = { for k, v in aws_nat_gateway.nat : k => v.id }
  description = "NAT Gateway ID 맵 { AZ => NAT GW ID }. 후속 모듈에서 NAT GW IP 화이트리스트 또는 참조에 사용."
}