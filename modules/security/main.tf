resource "aws_security_group" "sg" {
  for_each = var.sg
  name     = each.value.name
  vpc_id   = var.vpc_id
}

resource "aws_security_group_rule" "sg_rules" {
  for_each = {
    for idx, rule in var.sg_rules :
    "${rule.sg_key}-${rule.type}-${rule.protocol}-${rule.from_port}-${rule.to_port}-${idx}" => rule
  }

  type              = each.value.type
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  security_group_id = aws_security_group.sg[each.value.sg_key].id

  description = try(each.value.description, null)

  cidr_blocks = (length(try(each.value.cidr_blocks, [])) > 0
    ? each.value.cidr_blocks
  : null)

  source_security_group_id = (try(each.value.source_sg_key, null) != null
    ? aws_security_group.sg[each.value.source_sg_key].id
  : null)
}

locals {
  # var.nacls는 { nacl_key => { subnet_ids = [...], rules = [...] } } 중첩 구조다
  # association과 rule은 "항목 1개 = 리소스 1개"이므로
  # for_each에 쓰려면 중첩 구조를 먼저 평탄화(flatten)해야 한다

  nacl_subnet_pairs = flatten([
    for nacl_key, nacl in var.nacls : [
      for subnet_id in nacl.subnet_ids : {
        nacl_key  = nacl_key
        subnet_id = subnet_id
      }
    ]
  ])

  nacl_rules = flatten([
    for nacl_key, nacl in var.nacls : [
      # merge()로 nacl_key를 rule 객체에 추가한다
      # 이유: rule 객체만으로는 어느 NACL에 속하는지 알 수 없기 때문
      for rule in nacl.rules : merge(rule, { nacl_key = nacl_key })
    ]
  ])
}

resource "aws_network_acl" "nacl" {
  # var.nacls의 key마다 NACL 1개 생성
  # var.nacls = {} (default)이면 아무것도 생성되지 않는다
  for_each = var.nacls
  vpc_id   = var.vpc_id
}

resource "aws_network_acl_association" "nacl_association" {
  # nacl_subnet_pairs: [{ nacl_key="public", subnet_id="subnet-xxx" }, ...]
  # for_each는 map이 필요하므로 "public-subnet-xxx" 형태로 유니크 key를 만든다
  for_each = {
    for pair in local.nacl_subnet_pairs :
    "${pair.nacl_key}-${pair.subnet_id}" => pair
  }

  network_acl_id = aws_network_acl.nacl[each.value.nacl_key].id
  subnet_id      = each.value.subnet_id
}

resource "aws_network_acl_rule" "nacl_rule" {
  # key: "public-ingress-100" 형태 → NACL별·방향별·번호별 유니크 보장
  for_each = {
    for rule in local.nacl_rules :
    "${rule.nacl_key}-${rule.egress ? "egress" : "ingress"}-${rule.rule_number}" => rule
  }

  network_acl_id = aws_network_acl.nacl[each.value.nacl_key].id
  rule_number    = each.value.rule_number
  egress         = each.value.egress
  protocol       = each.value.protocol
  rule_action    = each.value.rule_action
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}