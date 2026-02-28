# modules/vpc/outputs.tf
# 이 모듈이 외부로 노출하는 값을 선언합니다.
# 다른 모듈이 `module.vpc.vpc_id` 형태로 참조합니다.
# 이유: outputs.tf가 없으면 모듈 간 참조가 불가능하여 각 모듈이 독립적으로 동작할 수 없습니다.

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "생성된 VPC의 ID. 서브넷, 보안그룹, NAT Gateway, IGW 등 대부분의 네트워크 리소스에서 필수로 참조합니다."
  # 예: module.subnet에서 vpc_id = module.vpc.vpc_id 형태로 사용됩니다.
}

output "vpc_cidr_block" {
  value       = aws_vpc.main.cidr_block
  description = "VPC의 CIDR 블록. 서브넷 CIDR 계획 또는 보안그룹 내부 트래픽 허용 규칙 정의 시 참조합니다."
  # 예: aws_security_group의 ingress cidr_blocks = [module.vpc.vpc_cidr_block]
}