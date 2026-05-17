#!/usr/bin/env bash
# deploy.sh — LGTM + OTel + Flask 통합 배포 오케스트레이터
#
# 옵션 (둘 중 하나 또는 없음 — 없으면 현재 kubectl 컨텍스트 사용):
#   CREATE_GKE=1  → fsi* GCP 프로젝트에 lgtm-cluster GKE 생성
#   USE_KIND=1    → 로컬 docker 위에 kind 클러스터(lgtm) + metallb + 컨트롤 플레인 메트릭
#
# DRY_RUN=1     명령어만 echo
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export USE_KIND="${USE_KIND:-0}"
export CREATE_GKE="${CREATE_GKE:-0}"
export WITH_CILIUM="${WITH_CILIUM:-0}"
export DRY_RUN="${DRY_RUN:-0}"

if [ "${WITH_CILIUM}" = "1" ] && [ "${USE_KIND}" != "1" ]; then
  echo "[deploy] WITH_CILIUM=1 은 USE_KIND=1 과 함께 사용해야 합니다." >&2
  exit 1
fi

if [ "${CREATE_GKE}" = "1" ] && [ "${USE_KIND}" = "1" ]; then
  echo "[deploy] ERROR: CREATE_GKE 와 USE_KIND 를 동시에 지정할 수 없습니다." >&2
  exit 1
fi

echo "════════════════════════════════════════════════════════"
echo "  LGTM + OTel + Flask 자동 배포 시작"
echo "    DRY_RUN=${DRY_RUN}  CREATE_GKE=${CREATE_GKE}  USE_KIND=${USE_KIND}"
echo "════════════════════════════════════════════════════════"

steps=()

# 0) 클러스터 생성 (옵션)
[ "${CREATE_GKE}" = "1" ] && steps+=("create-gke.sh")
[ "${USE_KIND}"   = "1" ] && steps+=("create-kind.sh")

steps+=(
  "00-prereq.sh"
  "01-repos.sh"
)

# 1c) cilium 먼저 설치 (CNI — 노드 Ready 전제)
[ "${WITH_CILIUM}" = "1" ] && steps+=("01c-cilium.sh")

# 1b) kind metallb 설치 (LoadBalancer 지원 — CNI 이후)
[ "${USE_KIND}" = "1" ] && steps+=("01b-metallb.sh")

steps+=(
  "02-lgtm.sh"
  "03-otel.sh"
)

# 3b) kind에서만 OTel agent(daemonset) 추가 (노드 로그/시스템 메트릭)
[ "${USE_KIND}" = "1" ] && steps+=("03b-otel-agent.sh")

steps+=(
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

if [ "${DRY_RUN}" != "1" ]; then
  GRAFANA_IP=$(kubectl -n monitoring get svc my-prom-grafana \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  FLASK_IP=$(kubectl -n flask-app get svc my-flask-app \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  echo "  Grafana   : http://${GRAFANA_IP}   (admin / Test1234)"
  echo "  대시보드  : http://${GRAFANA_IP}/d/flask-app-observability"
  echo "  Flask App : http://${FLASK_IP}"
  if [ "${USE_KIND}" = "1" ]; then
    echo ""
    echo "  ※ kind: 위 IP는 docker network(예 172.18.x.x) 안의 주소입니다."
    echo "    호스트에서는 그대로 접근 가능. 호스트 밖(인터넷)에서 접근하려면"
    echo "    socat/ssh-tunnel 등으로 노출하세요."
  fi
  echo "════════════════════════════════════════════════════════"
fi
