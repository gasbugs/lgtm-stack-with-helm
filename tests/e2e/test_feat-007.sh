#!/usr/bin/env bash
# E2E: feat-007 — deploy.sh 오케스트레이터 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0

# 1) 파일 존재 + 문법 + 실행 권한
for f in deploy.sh scripts/00-prereq.sh scripts/01-repos.sh scripts/02-lgtm.sh scripts/03-otel.sh scripts/04-datasources.sh scripts/05-flask-app.sh scripts/06-traffic.sh; do
  [ -f "${f}" ] || { echo "FAIL: ${f} 없음"; fail=1; continue; }
  bash -n "${f}" 2>/dev/null || { echo "FAIL: ${f} 문법 오류"; fail=1; continue; }
  echo "PASS: ${f} 문법 OK"
done

# 2) DRY_RUN 실행 — 모든 단계가 호출되는지 확인
OUT=$(DRY_RUN=1 bash deploy.sh 2>&1 || true)
for marker in "00-prereq.sh" "01-repos.sh" "02-lgtm.sh" "03-otel.sh" "04-datasources.sh" "05-flask-app.sh" "06-traffic.sh"; do
  if echo "${OUT}" | grep -q "${marker}"; then
    echo "PASS: DRY_RUN ${marker} 실행됨"
  else
    echo "FAIL: DRY_RUN ${marker} 미실행"
    fail=1
  fi
done

# 핵심 helm/kubectl 명령어들이 DRY로 출력되는지
echo "${OUT}" | grep -q "helm upgrade --install loki" && echo "PASS: Loki helm 명령 출력" || { echo "FAIL: Loki helm 명령 없음"; fail=1; }
echo "${OUT}" | grep -q "helm upgrade --install tempo" && echo "PASS: Tempo helm 명령 출력" || { echo "FAIL: Tempo helm 명령 없음"; fail=1; }
echo "${OUT}" | grep -q "helm upgrade --install my-prom" && echo "PASS: kube-prometheus-stack helm 명령 출력" || { echo "FAIL: my-prom 없음"; fail=1; }
echo "${OUT}" | grep -q "helm upgrade --install otel-collector" && echo "PASS: OTel helm 명령 출력" || { echo "FAIL: OTel 없음"; fail=1; }

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-007 PASS ===="
  exit 0
else
  echo "==== feat-007 FAIL ===="
  exit 1
fi
