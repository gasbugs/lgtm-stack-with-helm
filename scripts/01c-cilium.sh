#!/usr/bin/env bash
# Cilium 설치 — kube-proxy 대체 + prometheus 메트릭 + Hubble L4-L7 관측성
set -euo pipefail

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[01c-cilium] DRY: $*"; else echo "[01c-cilium] $*"; "$@"; fi
}

run helm repo add cilium https://helm.cilium.io/ >/dev/null
run helm repo update >/dev/null

# kind control-plane 컨테이너 IP/포트 자동 추출 (kubeProxyReplacement 모드)
if [ "${DRY_RUN:-0}" = "1" ]; then
  API_HOST="lgtm-control-plane"
  API_PORT=6443
else
  API_HOST=$(docker inspect lgtm-control-plane --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
  API_PORT=6443
fi

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
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
  --set hubble.metrics.serviceMonitor.enabled=true \
  --set hubble.metrics.serviceMonitor.trustCRDsExist=true \
  --set prometheus.enabled=true \
  --set prometheus.serviceMonitor.enabled=true \
  --set prometheus.serviceMonitor.trustCRDsExist=true \
  --set operator.prometheus.enabled=true \
  --set operator.prometheus.serviceMonitor.enabled=true \
  --set operator.prometheus.serviceMonitor.trustCRDsExist=true

if [ "${DRY_RUN:-0}" != "1" ]; then
  echo "[01c-cilium] cilium 파드 준비 대기..."
  kubectl -n kube-system rollout status ds/cilium --timeout=180s || true
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=180s || true
fi

echo "[01c-cilium] 완료"
