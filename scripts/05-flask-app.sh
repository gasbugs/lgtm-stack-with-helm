#!/usr/bin/env bash
# 테스트 Flask 앱 배포
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[05-flask] DRY: $*"
  else
    echo "[05-flask] $*"
    "$@"
  fi
}

run kubectl apply -f "${ROOT}/manifests/flask-app.yaml"

if [ "${DRY_RUN:-0}" != "1" ]; then
  kubectl -n flask-app rollout status deploy/my-flask-app --timeout=180s || true
  echo "[05-flask] LoadBalancer 외부 IP 대기 중..."
  for i in {1..30}; do
    EXT=$(kubectl -n flask-app get svc my-flask-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "${EXT}" ]; then
      echo "[05-flask] 외부 IP: ${EXT}"
      echo "${EXT}" > "${ROOT}/.flask-external-ip"
      break
    fi
    sleep 5
  done
fi

echo "[05-flask] 완료"
