locals {
  # policy_jsons 평탄화: role_key + policy_name 조합으로 유니크 key 생성
  # 결과: { "app_role-secrets" => { role_key, policy_name, json }, ... }
  custom_policies = {
    for pair in flatten([
      for role_key, role in var.iam_roles : [
        for policy_name, json in role.policy_jsons : {
          role_key    = role_key
          policy_name = policy_name
          json        = json
        }
      ]
    ]) : "${pair.role_key}-${pair.policy_name}" => pair
  }

  # managed_policy_arns 평탄화: role_key + arn 조합으로 유니크 key 생성
  # 결과: { "app_role-arn:aws:iam::..." => { role_key, policy_arn }, ... }
  managed_attachments = {
    for pair in flatten([
      for role_key, role in var.iam_roles : [
        for arn in role.managed_policy_arns : {
          role_key   = role_key
          policy_arn = arn
        }
      ]
    ]) : "${pair.role_key}-${pair.policy_arn}" => pair
  }
}

# Role 생성
resource "aws_iam_role" "roles" {
  for_each           = var.iam_roles
  name               = each.value.name
  description        = each.value.description
  assume_role_policy = each.value.assume_role_policy  # Trust Policy JSON
}

# 커스텀 Policy 생성 (policy_jsons에서)
resource "aws_iam_policy" "custom" {
  for_each = local.custom_policies
  name     = "${each.value.role_key}-${each.value.policy_name}"
  policy   = each.value.json
}

# 커스텀 Policy → Role 연결
resource "aws_iam_role_policy_attachment" "custom" {
  for_each   = local.custom_policies
  role       = aws_iam_role.roles[each.value.role_key].name
  policy_arn = aws_iam_policy.custom[each.key].arn
}

# AWS Managed Policy → Role 연결
resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = local.managed_attachments
  role       = aws_iam_role.roles[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

# Instance Profile (EC2가 Role을 assume하기 위한 래퍼)
resource "aws_iam_instance_profile" "profiles" {
  for_each = var.iam_roles
  name     = "${each.value.name}-instance-profile"
  role     = aws_iam_role.roles[each.key].name
}
