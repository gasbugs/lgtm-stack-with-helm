#!/usr/bin/env bash
# MetalLB 설치 + kind docker network 대역에서 IP 풀 자동 산출
# (kind에서 LoadBalancer 서비스가 EXTERNAL-IP를 받도록 함)
set -euo pipefail

run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "[01b-metallb] DRY: $*"; else echo "[01b-metallb] $*"; "$@"; fi
}

# 1) MetalLB 매니페스트 설치
run kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[01b-metallb] DRY: kind docker network 검사 및 IPAddressPool 설치 (건너뜀)"
  exit 0
fi

echo "[01b-metallb] MetalLB 컨트롤러 준비 대기..."
kubectl -n metallb-system wait --for=condition=Available deploy/controller --timeout=180s
kubectl -n metallb-system rollout status ds/speaker --timeout=120s

# 2) kind 노드들이 사용하는 docker network 대역을 자동 추출
#    예: 172.18.0.0/16 → 172.18.255.200~250 풀로 할당
NET_CIDR=$(docker network inspect kind --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null | grep -v ':' | grep -v '^$' | head -1)
if [ -z "${NET_CIDR}" ]; then
  echo "[01b-metallb] ERROR: docker network 'kind' 를 찾을 수 없습니다 (kind 클러스터가 떠 있어야 합니다)." >&2
  exit 1
fi
PREFIX=$(echo "${NET_CIDR}" | awk -F. '{print $1"."$2}')
POOL_START="${PREFIX}.255.200"
POOL_END="${PREFIX}.255.250"
echo "[01b-metallb] kind docker network: ${NET_CIDR}"
echo "[01b-metallb] IP 풀: ${POOL_START} - ${POOL_END}"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${POOL_START}-${POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF

echo "[01b-metallb] 완료"
