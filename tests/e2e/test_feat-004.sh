#!/usr/bin/env bash
# E2E: feat-004 — OTel Collector values 렌더링 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0
F="values/otel-values.yaml"

[ -f "${F}" ] && echo "PASS: ${F} 존재" || { echo "FAIL: ${F} 없음"; exit 1; }

# helm template 렌더링
OUT=$(helm template otel-collector open-telemetry/opentelemetry-collector -n otel -f "${F}" 2>&1)
if [ $? -eq 0 ] && [ -n "${OUT}" ]; then
  echo "PASS: helm template 렌더링"
else
  echo "FAIL: helm template 렌더링"; echo "${OUT}" | tail -10; fail=1
fi

# 렌더링 결과에 핵심 구성요소 포함 검증
echo "${OUT}" | grep -q "loki-gateway.monitoring" && echo "PASS: Loki exporter 엔드포인트 포함" || { echo "FAIL: Loki exporter 누락"; fail=1; }
echo "${OUT}" | grep -q "my-prom-kube-prometheus-st-prometheus" && echo "PASS: Prometheus remotewrite 엔드포인트 포함" || { echo "FAIL: Prom 엔드포인트 누락"; fail=1; }
echo "${OUT}" | grep -q "tempo-distributor.monitoring" && echo "PASS: Tempo exporter 엔드포인트 포함" || { echo "FAIL: Tempo 엔드포인트 누락"; fail=1; }
echo "${OUT}" | grep -q "4317" && echo "PASS: OTLP gRPC 포트 4317 포함" || { echo "FAIL: 4317 누락"; fail=1; }

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-004 PASS ===="
  exit 0
else
  echo "==== feat-004 FAIL ===="
  exit 1
fi
