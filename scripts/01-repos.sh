#!/usr/bin/env bash
# Helm 리포지토리 추가 및 네임스페이스 생성
set -euo pipefail

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[01-repos] DRY: $*"
  else
    echo "[01-repos] $*"
    "$@"
  fi
}

run helm repo add grafana https://grafana.github.io/helm-charts
run helm repo add grafana-community https://grafana-community.github.io/helm-charts
run helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
run helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
run helm repo update

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[01-repos] DRY: kubectl create ns monitoring"
  echo "[01-repos] DRY: kubectl create ns otel"
else
  kubectl create ns monitoring --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns otel       --dry-run=client -o yaml | kubectl apply -f -
fi

echo "[01-repos] 완료"
