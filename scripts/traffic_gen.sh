#!/usr/bin/env bash
# 트래픽 제너레이터 — Flask 데모 앱에 무작위 엔드포인트로 요청
# 사용법: bash traffic_gen.sh [BASE_URL]
# 기본 URL: http://localhost
set -uo pipefail

DEFAULT_SERVER="http://localhost"
SERVER="${1:-${DEFAULT_SERVER}}"

paths=(
  "/health"
  "/"
  "/to_stack"
  "/cpu_task"
  "/random_status"
  "/random_sleep"
  "/error_test"
  "/complex-operation"
)

trap 'echo; echo "[traffic_gen] 종료"; exit 0' INT TERM

echo "[traffic_gen] target = ${SERVER}"
while true; do
  p="${paths[$((RANDOM % ${#paths[@]}))]}"
  echo "Sending request to: ${SERVER}${p}"
  curl -s -o /dev/null -w "  -> HTTP %{http_code} (%{time_total}s)\n" "${SERVER}${p}" || true
  sleep 1
done
