#!/usr/bin/env bash
# OTel Collector DaemonSet — 노드 컨테이너 로그/시스템 메트릭 수집
# USE_KIND=1 일 때 deploy.sh가 추가 실행
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[03b-otel-agent] DRY: $*"; else echo "[03b-otel-agent] $*"; "$@"; fi
}

run helm upgrade --install otel-agent \
  open-telemetry/opentelemetry-collector \
  -n otel --create-namespace \
  -f "${ROOT}/values/otel-agent-values.yaml"

if [ "${DRY_RUN:-0}" != "1" ]; then
  kubectl -n otel rollout status ds/otel-agent-opentelemetry-collector-agent --timeout=180s || \
  kubectl -n otel rollout status ds/otel-agent --timeout=180s || true
fi

echo "[03b-otel-agent] 완료"
