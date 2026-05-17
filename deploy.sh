#!/usr/bin/env bash
# deploy.sh — LGTM + OTel + Flask 전체 배포 오케스트레이터
# 사용법:
#   bash deploy.sh             # 실제 배포
#   DRY_RUN=1 bash deploy.sh   # 명령어만 출력하고 실행하지 않음
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

steps=(
  "00-prereq.sh"
  "01-repos.sh"
  "02-lgtm.sh"
  "03-otel.sh"
  "04-datasources.sh"
  "05-flask-app.sh"
  "06-traffic.sh"
)

echo "════════════════════════════════════════════════════════"
echo "  LGTM + OTel + Flask 자동 배포 시작 (DRY_RUN=${DRY_RUN:-0})"
echo "════════════════════════════════════════════════════════"

for s in "${steps[@]}"; do
  echo ""
  echo "──── ${s} ────"
  bash "${ROOT}/scripts/${s}"
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  배포 완료"
echo "  Grafana admin 비밀번호: Test1234"
echo "  접속:"
echo "    kubectl -n monitoring get svc my-prom-grafana"
echo "════════════════════════════════════════════════════════"
