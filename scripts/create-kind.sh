#!/usr/bin/env bash
# kind 클러스터 생성
# 사용: bash scripts/create-kind.sh [CLUSTER_NAME]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLUSTER="${1:-lgtm}"
if [ "${WITH_CILIUM:-0}" = "1" ]; then
  CONFIG="${ROOT}/kind/cluster-cilium.yaml"
  echo "[create-kind] WITH_CILIUM=1 → CNI 없는 config 사용 (cilium이 설치 후 CNI 담당)"
else
  CONFIG="${ROOT}/kind/cluster.yaml"
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[create-kind] DRY: kind create cluster --name ${CLUSTER} --config ${CONFIG}"
  exit 0
fi

if ! command -v kind >/dev/null 2>&1; then
  echo "[create-kind] ERROR: kind 가 설치되어 있지 않습니다." >&2
  echo "  설치: go install sigs.k8s.io/kind@latest  또는  brew install kind" >&2
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo "[create-kind] 기존 클러스터 '${CLUSTER}' 존재 — 컨텍스트만 활성화"
else
  echo "[create-kind] 새 클러스터 생성 중: ${CLUSTER}"
  kind create cluster --name "${CLUSTER}" --config "${CONFIG}" --wait 120s
fi

kubectl cluster-info --context "kind-${CLUSTER}"
kubectl get nodes
echo "[create-kind] 완료"
