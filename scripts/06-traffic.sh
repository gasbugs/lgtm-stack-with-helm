#!/usr/bin/env bash
# 트래픽 제너레이터 백그라운드 실행
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[06-traffic] DRY: traffic_gen.sh 백그라운드 실행 (스킵)"
  exit 0
fi

EXT_FILE="${ROOT}/.flask-external-ip"
if [ ! -f "${EXT_FILE}" ]; then
  echo "[06-traffic] WARN: .flask-external-ip 파일 없음 — 외부 IP를 인자로 전달하세요" >&2
  echo "[06-traffic] 사용법: bash scripts/06-traffic.sh http://<EXTERNAL-IP>" >&2
  TARGET="${1:-}"
  if [ -z "${TARGET}" ]; then exit 1; fi
else
  TARGET="${1:-http://$(cat "${EXT_FILE}")}"
fi

LOG="${ROOT}/.traffic.log"
PIDFILE="${ROOT}/.traffic.pid"

if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
  echo "[06-traffic] 이미 실행 중 (PID $(cat "${PIDFILE}")). 중단하려면 bash scripts/06-traffic.sh stop"
  exit 0
fi

if [ "${1:-}" = "stop" ]; then
  if [ -f "${PIDFILE}" ]; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    rm -f "${PIDFILE}"
    echo "[06-traffic] 중단됨"
  fi
  exit 0
fi

nohup bash "${ROOT}/scripts/traffic_gen.sh" "${TARGET}" >"${LOG}" 2>&1 &
echo $! > "${PIDFILE}"
echo "[06-traffic] PID $(cat "${PIDFILE}") — 로그: ${LOG}"
