#!/bin/bash
set -e

# ============================================================
# Terraform Remote Backend Bootstrap
# S3 버킷과 DynamoDB 테이블을 생성한다.
# 이미 존재하면 스킵하므로 여러 번 실행해도 안전하다 (멱등성).
# ============================================================

BUCKET="bootstrap-ljp-practice-terraform-state"       # 변경 필요: 전역 유일한 버킷 이름
TABLE="terraform-state-lock"
REGION="ap-northeast-2"

echo "==> [1/4] AWS 자격증명 확인"
aws sts get-caller-identity --query "Account" --output text > /dev/null
echo "OK"

# ------------------------------------------------------------------
# S3 버킷 생성
# ------------------------------------------------------------------
echo "==> [2/4] S3 버킷 확인 / 생성: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "이미 존재함, 스킵"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  echo "생성 완료"
fi

echo "==> [3/4] S3 버전 관리 활성화"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "OK"

# ------------------------------------------------------------------
# DynamoDB 테이블 생성 (State Lock)
# ------------------------------------------------------------------
echo "==> [4/4] DynamoDB 테이블 확인 / 생성: $TABLE"
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null; then
  echo "이미 존재함, 스킵"
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "생성 완료"
fi

echo ""
echo "============================================"
echo "Bootstrap 완료"
echo "S3 Bucket : $BUCKET"
echo "DynamoDB  : $TABLE"
echo "Region    : $REGION"
echo ""
echo "이제 envs/dev/1-network 부터 시작하세요."
echo "  cd envs/dev/1-network && terraform init && terraform apply"
echo "============================================"
