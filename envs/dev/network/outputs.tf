output "vpc_id" {
  value       = module.main.vpc_id
  description = "생성한 VPC ID"
}

output "vpc_cidr_block" {
  value       = module.main.vpc_cidr_block
  description = "VPC CIDR 블록"
}

output "public_subnet_ids" {
  value       = module.main.public_subnet_ids
  description = "Public Subnet ID 목록. ALB 배치에 사용."
}

output "private_nat_subnet_ids" {
  value       = module.main.private_nat_subnet_ids
  description = "Private NAT Subnet ID 목록. ASG(EC2) 배치에 사용."
}

output "private_full_subnet_ids" {
  value       = module.main.private_full_subnet_ids
  description = "Private Full Subnet ID 목록. RDS, ElastiCache 배치에 사용."
}

output "nat_gateway_ids" {
  value       = module.main.nat_gateway_ids
  description = "NAT Gateway ID 맵 { AZ => NAT GW ID }"
}
