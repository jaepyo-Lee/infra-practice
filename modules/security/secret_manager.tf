resource "aws_secretsmanager_secret" "secret_manager" {
  for_each                = var.secret_manager_meta
  name                    = each.value.name
  description             = each.value.description
  recovery_window_in_days = each.value.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "secret_manager_version" {
  for_each = var.secret_manager_meta
  secret_id = aws_secretsmanager_secret.secret_manager[each.key].id
  secret_string = each.value.secret_value
}