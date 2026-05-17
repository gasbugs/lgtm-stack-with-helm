#!/usr/bin/env bash
# Grafana 데이터소스 ConfigMap 적용 (sidecar가 자동 로드)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[04-ds] DRY: $*"
  else
    echo "[04-ds] $*"
    "$@"
  fi
}

run kubectl apply -f "${ROOT}/manifests/grafana-datasources.yaml"
echo "[04-ds] 완료 — Grafana sidecar가 30초 이내 데이터소스를 자동 로드합니다"
