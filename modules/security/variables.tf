variable "vpc_id" {
  type        = string
  description = "속한 VPC ID"
}

variable "sg" {
  type = map(object({
    name = string
  }))
  description = "생성할 Security Group 목록. key가 sg_rules의 sg_key와 일치해야 함"
}

variable "sg_rules" {
  type = list(object({
    sg_key        = string
    type          = string
    from_port     = number
    to_port       = number
    protocol      = optional(string, "tcp")
    cidr_blocks   = optional(list(string), [])
    description   = optional(string, null)
    source_sg_key = optional(string, null)
  }))
  description = "Security Group 규칙 목록"
}

variable "nacls" {
  # map의 key = NACL 이름 (예: "public", "private_app", "private_db")
  # key별로 NACL 리소스 1개가 생성된다
  type = map(object({
    subnet_ids = list(string) # 이 NACL을 연결할 서브넷 ID 목록
    rules = list(object({
      rule_number = number # 평가 순서. 낮을수록 먼저 평가됨
      egress      = bool   # true = outbound, false = inbound
      protocol    = string # "tcp", "udp", "-1"(전체)
      rule_action = string # "allow" 또는 "deny"
      cidr_block  = string # 대상 IP 범위
      from_port   = optional(number, null)
      to_port     = optional(number, null)
    }))
  }))
  description = "생성할 NACL 맵. default={}이면 NACL을 생성하지 않음 (선택 생성 가능)"
  default     = {}
}


variable "iam_roles" {
  type = map(object({
    name                = string
    description         = optional(string, null)
    assume_role_policy  = string           # Trust Policy JSON 문자열
    policy_jsons        = optional(map(string), {})    # 커스텀 policy: { policy이름 = JSON문자열 }
    managed_policy_arns = optional(list(string), [])   # AWS Managed Policy ARN 목록
  }))
  description = "생성할 IAM Role 목록. default={}이면 생성하지 않음"
  default     = {}
}
