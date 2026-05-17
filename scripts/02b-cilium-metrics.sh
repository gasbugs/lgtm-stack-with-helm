#!/usr/bin/env bash
# Cilium 설치 (2단계) — LGTM(prometheus-operator CRD) 깔린 후 ServiceMonitor 활성화
set -euo pipefail

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[02b-cilium-metrics] DRY: $*"; else echo "[02b-cilium-metrics] $*"; "$@"; fi
}

# Hubble metrics는 chart key가 list라 --set 으로 넣기 까다로움 → values file로
TMP=$(mktemp)
cat > "${TMP}" <<'YAML'
hubble:
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction
    serviceMonitor:
      enabled: true
prometheus:
  serviceMonitor:
    enabled: true
operator:
  prometheus:
    serviceMonitor:
      enabled: true
YAML

run helm upgrade cilium cilium/cilium \
  --version 1.16.4 \
  --namespace kube-system \
  --reuse-values \
  -f "${TMP}"

rm -f "${TMP}"

if [ "${DRY_RUN:-0}" != "1" ]; then
  kubectl -n kube-system rollout status ds/cilium --timeout=120s || true
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=120s || true
fi

echo "[02b-cilium-metrics] 완료 — ServiceMonitor 활성화됨"
