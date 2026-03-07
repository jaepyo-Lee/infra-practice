#!/bin/bash
# destroy-all.sh
# 초기화된 모든 Terraform 모듈을 역의존성 순서로 삭제한다.
# 이 스크립트는 Claude의 /destroy-all 스킬이 자동 생성합니다.
# 생성일: 2026-02-28 / 수정일: 2026-03-07 (destroy-all 스킬 재실행 확인)

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

trap 'echo "[ERROR] 삭제 실패: $CURRENT_DIR"; exit 1' ERR

destroy_module() {
  local dir="$1"
  if [ ! -d "$dir/.terraform" ]; then
    echo "[SKIP] 초기화되지 않은 모듈: $dir"
    return
  fi
  CURRENT_DIR="$dir"
  echo "[DESTROY] 삭제 시작: $dir"
  cd "$dir"
  terraform destroy -auto-approve
  echo "[DONE] 삭제 완료: $dir"
  cd "$ROOT_DIR"
}

echo "=============================="
echo "  Terraform 전체 리소스 삭제"
echo "=============================="
echo ""
echo "삭제 전 현재 AWS 프로파일을 확인하세요:"
echo "  aws sts get-caller-identity"
echo ""
read -p "계속 진행하시겠습니까? (yes 입력): " confirm
if [ "$confirm" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

# ----------------------------------------
# 삭제 순서: 의존성 역순 (높은 레이어 먼저)
# ----------------------------------------

# Phase 6 — Observability
# destroy_module "$ROOT_DIR/envs/dev/monitoring"

# Phase 5 — Database Tier
# destroy_module "$ROOT_DIR/envs/dev/database"

# Phase 4 — Application Tier
# destroy_module "$ROOT_DIR/envs/dev/app"

# Phase 3 — Web Tier
destroy_module "$ROOT_DIR/envs/dev/web"

# Phase 2 — Security Layer
destroy_module "$ROOT_DIR/envs/dev/security"

# Phase 1 — Network Foundation
destroy_module "$ROOT_DIR/envs/dev/network"

echo ""
echo "=============================="
echo "  모든 리소스 삭제 완료"
echo "=============================="
