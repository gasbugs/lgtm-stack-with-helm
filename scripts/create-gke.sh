#!/usr/bin/env bash
# GKE 클러스터 생성 — fsi 프로젝트
# 사용법: bash scripts/create-gke.sh [CLUSTER_NAME] [ZONE]
set -euo pipefail

CLUSTER="${1:-lgtm-cluster}"
ZONE="${2:-us-central1-a}"

PROJECT=$(gcloud projects list --filter="projectId:fsi*" --format="value(projectId)" | head -1)
if [ -z "${PROJECT}" ]; then
  echo "[create-gke] ERROR: fsi*로 시작하는 GCP 프로젝트를 찾을 수 없습니다" >&2
  exit 1
fi
echo "[create-gke] 프로젝트: ${PROJECT}"
echo "[create-gke] 클러스터: ${CLUSTER} (zone=${ZONE})"

if gcloud container clusters describe "${CLUSTER}" --zone="${ZONE}" --project="${PROJECT}" >/dev/null 2>&1; then
  echo "[create-gke] 이미 존재 — 자격 증명만 갱신"
else
  echo "[create-gke] 새 클러스터 생성 중 (5~10분 소요)..."
  gcloud container clusters create "${CLUSTER}" \
    --project="${PROJECT}" \
    --zone="${ZONE}" \
    --num-nodes=3 \
    --machine-type=e2-standard-4 \
    --disk-type=pd-balanced \
    --disk-size=50 \
    --release-channel=regular \
    --enable-ip-alias
fi

gcloud container clusters get-credentials "${CLUSTER}" --zone="${ZONE}" --project="${PROJECT}"
kubectl cluster-info
echo "[create-gke] 완료"
