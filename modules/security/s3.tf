resource "aws_s3_bucket" "s3_bucket" {
  for_each      = var.s3_buckets
  bucket        = each.value.bucket_name
  force_destroy = each.value.force_destroy
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  for_each = var.s3_buckets

  bucket                  = aws_s3_bucket.s3_bucket[each.key].id
  block_public_acls       = each.value.block_public_acls
  ignore_public_acls      = each.value.ignore_public_acls
  block_public_policy     = each.value.block_public_policy
  restrict_public_buckets = each.value.restrict_public_buckets
}

resource "aws_s3_bucket_policy" "policy" {
  for_each = { for k, v in var.s3_buckets : k => v if v.bucket_policy_json != null }

  bucket = aws_s3_bucket.s3_bucket[each.key].id
  policy = each.value.bucket_policy_json
}