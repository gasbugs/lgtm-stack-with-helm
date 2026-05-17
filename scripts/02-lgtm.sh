#!/usr/bin/env bash
# LGTM 백엔드 설치: Loki, Tempo, kube-prometheus-stack
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[02-lgtm] DRY: $*"
  else
    echo "[02-lgtm] $*"
    "$@"
  fi
}

run helm upgrade --install loki grafana/loki \
  -n monitoring --create-namespace \
  -f "${ROOT}/values/loki-values.yaml"

run helm upgrade --install tempo grafana-community/tempo-distributed \
  -n monitoring \
  -f "${ROOT}/values/tempo-values.yaml"

run helm upgrade --install my-prom prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${ROOT}/values/kube-prom-values.yaml"

if [ "${DRY_RUN:-0}" != "1" ]; then
  echo "[02-lgtm] 파드 준비 대기 중..."
  kubectl -n monitoring rollout status deploy/my-prom-grafana --timeout=300s || true
  kubectl -n monitoring wait --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=300s || true
fi

echo "[02-lgtm] 완료"
