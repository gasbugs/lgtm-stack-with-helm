#!/usr/bin/env bash
# cleanup.sh — 배포된 모든 리소스 삭제
# 사용법: bash cleanup.sh [--keep-ns]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEEP_NS=0
[ "${1:-}" = "--keep-ns" ] && KEEP_NS=1

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[cleanup] DRY: $*"
  else
    echo "[cleanup] $*"
    "$@" || true
  fi
}

echo "════════════════════════════════════════════════════════"
echo "  cleanup 시작 (DRY_RUN=${DRY_RUN:-0})"
echo "════════════════════════════════════════════════════════"

# 트래픽 제너레이터 중단
if [ -f "${ROOT}/.traffic.pid" ]; then
  PID=$(cat "${ROOT}/.traffic.pid" 2>/dev/null || echo "")
  if [ -n "${PID}" ] && kill -0 "${PID}" 2>/dev/null; then
    run kill "${PID}"
  fi
  rm -f "${ROOT}/.traffic.pid"
fi

# 역순 삭제
run kubectl delete -f "${ROOT}/manifests/flask-app.yaml" --ignore-not-found
run kubectl delete -f "${ROOT}/manifests/grafana-datasources.yaml" --ignore-not-found
run helm uninstall -n otel       otel-collector
run helm uninstall -n monitoring my-prom
run helm uninstall -n monitoring tempo
run helm uninstall -n monitoring loki

if [ "${KEEP_NS}" -eq 0 ]; then
  run kubectl delete ns otel       --ignore-not-found
  run kubectl delete ns monitoring --ignore-not-found
  run kubectl delete ns flask-app  --ignore-not-found
else
  echo "[cleanup] --keep-ns 지정 — 네임스페이스 보존"
fi

rm -f "${ROOT}/.flask-external-ip" "${ROOT}/.traffic.log"

echo "[cleanup] 완료"
