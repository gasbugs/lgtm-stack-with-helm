#!/usr/bin/env bash
# E2E: feat-002 — LGTM Helm values 렌더링
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0

render() {
  local desc="$1" release="$2" chart="$3" vals="$4"
  if helm template "${release}" "${chart}" -n monitoring -f "${vals}" >/dev/null 2>&1; then
    echo "PASS: ${desc}"
  else
    echo "FAIL: ${desc}"
    helm template "${release}" "${chart}" -n monitoring -f "${vals}" 2>&1 | tail -10
    fail=1
  fi
}

render "Loki SingleBinary 렌더링" loki grafana/loki values/loki-values.yaml
render "Tempo distributed 렌더링" tempo grafana-community/tempo-distributed values/tempo-values.yaml
render "kube-prometheus-stack 렌더링" my-prom prometheus-community/kube-prometheus-stack values/kube-prom-values.yaml

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-002 PASS ===="
  exit 0
else
  echo "==== feat-002 FAIL ===="
  exit 1
fi
