#!/bin/bash
# apply-all.sh
# 모든 Terraform 모듈을 의존성 순서대로 init → apply 한다.
# 이 스크립트는 Claude의 /destroy-all 스킬이 자동 생성합니다.
# 생성일: 2026-02-28

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

trap 'echo "[ERROR] 적용 실패: $CURRENT_DIR"; exit 1' ERR

apply_module() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "[SKIP] 디렉토리 없음: $dir"
    return
  fi
  CURRENT_DIR="$dir"
  echo "[APPLY] 시작: $dir"
  cd "$dir"
  terraform init -reconfigure
  terraform apply -auto-approve
  echo "[DONE] 완료: $dir"
  cd "$ROOT_DIR"
}

echo "=============================="
echo "  Terraform 전체 리소스 생성"
echo "=============================="
echo ""
echo "적용 전 현재 AWS 프로파일을 확인하세요:"
echo "  aws sts get-caller-identity"
echo ""
read -p "계속 진행하시겠습니까? (yes 입력): " confirm
if [ "$confirm" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

# ----------------------------------------
# 생성 순서: 의존성 순서 (낮은 레이어 먼저)
# ----------------------------------------

# Phase 1 — Network Foundation
apply_module "$ROOT_DIR/envs/dev/vpc"

# Phase 2 — Security Layer
 apply_module "$ROOT_DIR/envs/dev/security"

# Phase 3 — Web Tier
 apply_module "$ROOT_DIR/envs/dev/web"

# Phase 4 — Application Tier
# apply_module "$ROOT_DIR/envs/dev/app"

# Phase 5 — Database Tier
# apply_module "$ROOT_DIR/envs/dev/database"

# Phase 6 — Observability
# apply_module "$ROOT_DIR/envs/dev/monitoring"

echo ""
echo "=============================="
echo "  모든 리소스 생성 완료"
echo "=============================="
