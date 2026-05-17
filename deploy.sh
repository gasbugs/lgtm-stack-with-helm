#!/usr/bin/env bash
# deploy.sh — LGTM + OTel + Flask 전체 배포 오케스트레이터
#
# 사용법:
#   bash deploy.sh                     # 기본 (클러스터는 이미 있다고 가정)
#   CREATE_GKE=1 bash deploy.sh        # GKE 클러스터까지 자동 생성 후 배포
#   DRY_RUN=1 bash deploy.sh           # 명령어만 출력하고 실행하지 않음
#
# 환경 변수:
#   CREATE_GKE   1이면 fsi* GCP 프로젝트에 lgtm-cluster를 자동 생성
#   GKE_CLUSTER  클러스터 이름 (기본 lgtm-cluster)
#   GKE_ZONE     zone (기본 us-central1-a)
#   DRY_RUN      1이면 명령어만 echo
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "════════════════════════════════════════════════════════"
echo "  LGTM + OTel + Flask 자동 배포 시작"
echo "    DRY_RUN=${DRY_RUN:-0}  CREATE_GKE=${CREATE_GKE:-0}"
echo "════════════════════════════════════════════════════════"

steps=()

# 0) GKE 클러스터 자동 생성 (옵션)
if [ "${CREATE_GKE:-0}" = "1" ]; then
  steps+=("create-gke.sh")
fi

steps+=(
  "00-prereq.sh"
  "01-repos.sh"
  "02-lgtm.sh"
  "03-otel.sh"
  "04-datasources.sh"
  "05-flask-app.sh"
  "06-traffic.sh"
)

for s in "${steps[@]}"; do
  echo ""
  echo "──── ${s} ────"
  bash "${ROOT}/scripts/${s}"
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  배포 완료"
echo "════════════════════════════════════════════════════════"

if [ "${DRY_RUN:-0}" != "1" ]; then
  GRAFANA_IP=$(kubectl -n monitoring get svc my-prom-grafana \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  FLASK_IP=$(kubectl -n flask-app get svc my-flask-app \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  echo "  Grafana   : http://${GRAFANA_IP}   (admin / Test1234)"
  echo "  대시보드  : http://${GRAFANA_IP}/d/flask-app-observability"
  echo "  Flask App : http://${FLASK_IP}"
  echo "════════════════════════════════════════════════════════"
fi
