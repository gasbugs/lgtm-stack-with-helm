#!/usr/bin/env bash
# 프로젝트용 init.sh 래퍼 — my-harness init.sh로 위임
# 사용법: bash init.sh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_INIT="/Users/gasbugs/my-harness/init.sh"

if [ ! -f "${HARNESS_INIT}" ]; then
  echo "[init.sh] ERROR: harness init.sh를 찾을 수 없습니다: ${HARNESS_INIT}" >&2
  exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT}" bash "${HARNESS_INIT}"
