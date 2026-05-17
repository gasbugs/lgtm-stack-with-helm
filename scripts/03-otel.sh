#!/usr/bin/env bash
# OpenTelemetry Collector 배포
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[03-otel] DRY: $*"
  else
    echo "[03-otel] $*"
    "$@"
  fi
}

run helm upgrade --install otel-collector \
  open-telemetry/opentelemetry-collector \
  -n otel --create-namespace \
  -f "${ROOT}/values/otel-values.yaml"

if [ "${DRY_RUN:-0}" != "1" ]; then
  kubectl -n otel rollout status deploy/otel-collector-opentelemetry-collector --timeout=180s || true
fi

echo "[03-otel] 완료"
