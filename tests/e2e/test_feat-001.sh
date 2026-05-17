#!/usr/bin/env bash
# E2E: feat-001 — 프로젝트 구조 및 init.sh 래퍼
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: ${desc}"
  else
    echo "FAIL: ${desc}"
    fail=1
  fi
}

check "init.sh 존재 및 실행 권한" test -x "${ROOT}/init.sh"
check "feature-list.json 존재" test -f "${ROOT}/feature-list.json"
check "scripts/ 디렉터리 존재" test -d "${ROOT}/scripts"
check "values/ 디렉터리 존재" test -d "${ROOT}/values"
check "manifests/ 디렉터리 존재" test -d "${ROOT}/manifests"
check "tests/e2e/ 디렉터리 존재" test -d "${ROOT}/tests/e2e"
check "init.sh 정상 종료(코드 0)" bash "${ROOT}/init.sh"

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-001 PASS ===="
  exit 0
else
  echo "==== feat-001 FAIL ===="
  exit 1
fi
