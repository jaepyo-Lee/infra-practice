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
