#!/usr/bin/env bash
# E2E: feat-003 — Grafana datasource ConfigMap 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

fail=0
F="manifests/grafana-datasources.yaml"

if [ ! -f "${F}" ]; then echo "FAIL: ${F} 없음"; exit 1; fi
echo "PASS: 파일 존재"

# YAML 파싱 검증 (python yaml 사용)
if python3 -c "import yaml,sys; list(yaml.safe_load_all(open('${F}')))" 2>/dev/null; then
  echo "PASS: YAML 파싱"
else
  echo "FAIL: YAML 파싱"; fail=1
fi

# 라벨 grafana_datasource=1 존재 확인
if grep -q 'grafana_datasource: "1"' "${F}"; then
  echo "PASS: sidecar 라벨 존재 (grafana_datasource=1)"
else
  echo "FAIL: sidecar 라벨 누락"; fail=1
fi

# Loki/Tempo 데이터소스 둘 다 정의되어 있는지
if grep -q 'type: loki' "${F}" && grep -q 'type: tempo' "${F}"; then
  echo "PASS: Loki/Tempo 데이터소스 모두 정의"
else
  echo "FAIL: 데이터소스 누락"; fail=1
fi

# kubectl 클라이언트사이드 dry-run (서버 연결 없이)
if python3 -c "
import yaml,sys
docs = list(yaml.safe_load_all(open('${F}')))
assert len(docs) >= 1
cm = docs[0]
assert cm['kind'] == 'ConfigMap'
assert cm['metadata']['name'] == 'grafana-datasources-lgtm'
assert cm['metadata']['namespace'] == 'monitoring'
assert cm['metadata']['labels']['grafana_datasource'] == '1'
ds = yaml.safe_load(cm['data']['lgtm-datasources.yaml'])
names = [d['name'] for d in ds['datasources']]
assert 'Loki' in names and 'Tempo' in names
print('OK')
" >/dev/null 2>&1; then
  echo "PASS: ConfigMap 구조 검증 (오프라인)"
else
  echo "FAIL: ConfigMap 구조 검증"; fail=1
fi

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-003 PASS ===="
  exit 0
else
  echo "==== feat-003 FAIL ===="
  exit 1
fi
