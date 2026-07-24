#!/usr/bin/env bash
# cleanup.sh — 배포된 모든 리소스 삭제
# 옵션:
#   --keep-ns        네임스페이스 보존
#   --delete-kind    kind 클러스터까지 통째로 삭제 (kubectl/helm 단계 건너뜀)
#   --kind-addons    kind 전용 Cilium/MetalLB까지 삭제
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEEP_NS=0
DELETE_KIND=0
KIND_ADDONS=0
for arg in "$@"; do
  case "${arg}" in
    --keep-ns) KEEP_NS=1 ;;
    --delete-kind) DELETE_KIND=1 ;;
    --kind-addons) KIND_ADDONS=1 ;;
  esac
done

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[cleanup] DRY: $*"
  else echo "[cleanup] $*"; "$@" || true
  fi
}

echo "════════════════════════════════════════════════════════"
echo "  cleanup 시작 (DRY_RUN=${DRY_RUN:-0}  DELETE_KIND=${DELETE_KIND})"
echo "════════════════════════════════════════════════════════"

# 트래픽 제너레이터 중단
if [ -f "${ROOT}/.traffic.pid" ]; then
  PID=$(cat "${ROOT}/.traffic.pid" 2>/dev/null || echo "")
  [ -n "${PID}" ] && kill -0 "${PID}" 2>/dev/null && run kill "${PID}"
  rm -f "${ROOT}/.traffic.pid"
fi

# --delete-kind: 클러스터 통째로 삭제하고 끝
if [ "${DELETE_KIND}" -eq 1 ]; then
  run kind delete cluster --name lgtm
  rm -f "${ROOT}/.flask-external-ip" "${ROOT}/.traffic.log"
  echo "[cleanup] kind 클러스터 삭제 완료"
  exit 0
fi

# 매니페스트 삭제
run kubectl delete -f "${ROOT}/manifests/flask-app.yaml" --ignore-not-found
run kubectl delete -f "${ROOT}/manifests/flask-dashboard.yaml" --ignore-not-found
run kubectl delete -f "${ROOT}/manifests/k8s-system-dashboard.yaml" --ignore-not-found
run kubectl delete -f "${ROOT}/manifests/grafana-datasources.yaml" --ignore-not-found

# helm uninstall (역순)
run helm uninstall -n otel       otel-agent
run helm uninstall -n otel       otel-collector
run helm uninstall -n monitoring my-prom
run helm uninstall -n monitoring tempo
run helm uninstall -n monitoring loki

# 클러스터 네트워킹 애드온은 공유 GKE 클러스터에서 삭제하면 안 된다.
# kind 전용 정리임을 호출자가 명시한 경우에만 제거한다.
if [ "${KIND_ADDONS}" -eq 1 ]; then
  run helm uninstall -n kube-system cilium
  run kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml --ignore-not-found
fi

if [ "${KEEP_NS}" -eq 0 ]; then
  run kubectl delete ns otel           --ignore-not-found
  run kubectl delete ns monitoring     --ignore-not-found
  run kubectl delete ns flask-app      --ignore-not-found
  [ "${KIND_ADDONS}" -eq 1 ] && run kubectl delete ns metallb-system --ignore-not-found
else
  echo "[cleanup] --keep-ns 지정 — 네임스페이스 보존"
fi

rm -f "${ROOT}/.flask-external-ip" "${ROOT}/.traffic.log"
echo "[cleanup] 완료"
