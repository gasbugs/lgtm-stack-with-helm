#!/usr/bin/env bash
# E2E: feat-006 — traffic_gen.sh 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

F="scripts/traffic_gen.sh"
fail=0

[ -f "${F}" ] && echo "PASS: ${F} 존재" || { echo "FAIL: ${F} 없음"; exit 1; }
[ -x "${F}" ] && echo "PASS: 실행 권한" || { echo "FAIL: 실행 권한 없음"; fail=1; }
bash -n "${F}" && echo "PASS: bash 문법" || { echo "FAIL: bash 문법"; fail=1; }
grep -q '/complex-operation' "${F}" && echo "PASS: /complex-operation 경로 포함" || { echo "FAIL: /complex-operation 누락"; fail=1; }
grep -q '/health' "${F}" && echo "PASS: /health 경로 포함" || { echo "FAIL: /health 누락"; fail=1; }

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-006 PASS ===="
  exit 0
else
  echo "==== feat-006 FAIL ===="
  exit 1
fi
