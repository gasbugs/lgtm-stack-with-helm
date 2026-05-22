#!/usr/bin/env bash
# Helm 리포지토리 추가 및 네임스페이스 생성
# 네트워크 일시 장애로 helm repo update 가 실패해도 캐시된 차트로 진행 가능하게 함.
set -uo pipefail

# soft: 실패해도 멈추지 않음 (helm repo 작업 — 캐시 fallback 허용)
soft() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[01-repos] DRY: $*"
  else
    echo "[01-repos] $*"
    if ! "$@"; then
      echo "[01-repos] WARN: 위 명령 실패 — 캐시된 차트로 진행 (rc=$?)"
    fi
  fi
}

# hard: 반드시 성공해야 하는 명령 (네임스페이스 등)
hard() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[01-repos] DRY: $*"
  else
    echo "[01-repos] $*"
    "$@"
  fi
}

soft helm repo add grafana https://grafana.github.io/helm-charts
soft helm repo add grafana-community https://grafana-community.github.io/helm-charts
soft helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
soft helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
soft helm repo update

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[01-repos] DRY: kubectl create ns monitoring"
  echo "[01-repos] DRY: kubectl create ns otel"
else
  hard bash -c "kubectl create ns monitoring --dry-run=client -o yaml | kubectl apply -f -"
  hard bash -c "kubectl create ns otel       --dry-run=client -o yaml | kubectl apply -f -"
fi

echo "[01-repos] 완료"
