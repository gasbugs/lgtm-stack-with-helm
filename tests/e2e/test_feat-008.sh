#!/usr/bin/env bash
# E2E: feat-008 — cleanup.sh 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0
F="cleanup.sh"

[ -f "${F}" ] && echo "PASS: ${F} 존재" || { echo "FAIL: ${F} 없음"; exit 1; }
bash -n "${F}" && echo "PASS: bash 문법" || { echo "FAIL: bash 문법"; fail=1; }
[ -x "${F}" ] && echo "PASS: 실행 권한" || { echo "FAIL: 실행 권한 없음"; fail=1; }

OUT=$(DRY_RUN=1 bash "${F}" 2>&1 || true)
for marker in "helm uninstall -n otel otel-collector" "helm uninstall -n monitoring my-prom" "helm uninstall -n monitoring tempo" "helm uninstall -n monitoring loki"; do
  if echo "${OUT}" | grep -qF "${marker}"; then
    echo "PASS: DRY 출력에 '${marker}' 포함"
  else
    echo "FAIL: '${marker}' 누락"
    fail=1
  fi
done

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-008 PASS ===="
  exit 0
else
  echo "==== feat-008 FAIL ===="
  exit 1
fi
