#!/usr/bin/env bash
# Cilium 설치 (1단계) — CNI + Hubble만 우선 활성화. ServiceMonitor는 LGTM(CRD) 설치 후 02b 단계에서 활성화.
set -euo pipefail

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[01c-cilium] DRY: $*"; else echo "[01c-cilium] $*"; "$@"; fi
}

run helm repo add cilium https://helm.cilium.io/ >/dev/null
run helm repo update >/dev/null

if [ "${DRY_RUN:-0}" = "1" ]; then
  API_HOST="lgtm-control-plane"
else
  API_HOST=$(docker inspect lgtm-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
fi
API_PORT=6443

run helm upgrade --install cilium cilium/cilium \
  --version 1.16.4 \
  --namespace kube-system \
  --set k8sServiceHost="${API_HOST}" \
  --set k8sServicePort="${API_PORT}" \
  --set kubeProxyReplacement=true \
  --set ipam.mode=kubernetes \
  --set image.pullPolicy=IfNotPresent \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true

if [ "${DRY_RUN:-0}" != "1" ]; then
  echo "[01c-cilium] cilium 파드 준비 대기..."
  kubectl -n kube-system rollout status ds/cilium --timeout=180s || true
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=180s || true
fi

echo "[01c-cilium] 완료 (1단계 — ServiceMonitor 는 02b 에서 활성화)"
