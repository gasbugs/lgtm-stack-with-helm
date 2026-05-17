#!/usr/bin/env bash
# E2E: feat-009 — 전체 통합 검증
# 개별 feature 테스트들을 모두 실행하여 종합 결과를 출력
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

tests=(
  "tests/e2e/test_feat-001.sh"
  "tests/e2e/test_feat-002.sh"
  "tests/e2e/test_feat-003.sh"
  "tests/e2e/test_feat-004.sh"
  "tests/e2e/test_feat-005.sh"
  "tests/e2e/test_feat-006.sh"
  "tests/e2e/test_feat-007.sh"
  "tests/e2e/test_feat-008.sh"
)

pass=0
fail=0
failed=()

echo "════════════════════════════════════════════════════════"
echo "  통합 E2E 검증 시작"
echo "════════════════════════════════════════════════════════"

for t in "${tests[@]}"; do
  echo ""
  echo "──── ${t} ────"
  if bash "${t}"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    failed+=("${t}")
  fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  요약: PASS ${pass}개, FAIL ${fail}개"
if [ ${fail} -gt 0 ]; then
  echo "  실패한 테스트:"
  for t in "${failed[@]}"; do echo "    - ${t}"; done
  echo "════════════════════════════════════════════════════════"
  exit 1
fi
echo "  ==== ALL TESTS PASS ===="
echo "════════════════════════════════════════════════════════"
exit 0
