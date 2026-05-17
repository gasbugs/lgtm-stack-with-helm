#!/usr/bin/env bash
# Grafana DataSource + Dashboard ConfigMap 적용 (sidecar가 자동 로드)
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
run kubectl apply -f "${ROOT}/manifests/flask-dashboard.yaml"

# 재배포 시 기존 Loki datasource UID가 랜덤으로 남아있을 수 있어 강제 재로드
if [ "${DRY_RUN:-0}" != "1" ]; then
  GRAFANA_HOST=$(kubectl -n monitoring get svc my-prom-grafana \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "${GRAFANA_HOST}" ]; then
    # uid가 'loki' 가 아닌 임시 datasource가 남아있으면 삭제 (sidecar가 재생성)
    BAD_UIDS=$(curl -fsS -u admin:Test1234 "http://${GRAFANA_HOST}/api/datasources" 2>/dev/null \
      | jq -r '.[] | select(.type=="loki" and .uid!="loki") | .uid' || true)
    for uid in ${BAD_UIDS}; do
      echo "[04-ds] 잘못된 Loki datasource UID 정리: ${uid}"
      curl -fsS -u admin:Test1234 -X DELETE "http://${GRAFANA_HOST}/api/datasources/uid/${uid}" >/dev/null || true
    done
    # sidecar reload 트리거
    kubectl -n monitoring annotate configmap grafana-datasources-lgtm reload="$(date +%s)" --overwrite >/dev/null || true
  fi
fi

echo "[04-ds] 완료 — sidecar가 ConfigMap을 자동 로드합니다 (~30s)"
