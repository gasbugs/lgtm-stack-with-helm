#!/usr/bin/env bash
# 사전 도구 확인
set -euo pipefail
echo "[00-prereq] 도구 확인 중..."
missing=()
for t in kubectl helm jq; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "[00-prereq] ERROR: 누락된 도구: ${missing[*]}" >&2
  exit 1
fi
echo "[00-prereq] OK: kubectl, helm, jq 모두 사용 가능"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[00-prereq] DRY_RUN — kubectl cluster-info 건너뜀"
else
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[00-prereq] ERROR: 쿠버네티스 클러스터에 연결할 수 없습니다." >&2
    exit 1
  fi
  echo "[00-prereq] OK: 클러스터 연결 정상"
fi
