#!/usr/bin/env bash
# E2E: feat-005 — Flask 앱 매니페스트 검증
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

F="manifests/flask-app.yaml"
fail=0

[ -f "${F}" ] && echo "PASS: ${F} 존재" || { echo "FAIL: ${F} 없음"; exit 1; }

# 오프라인 YAML 검증
python3 - <<PY
import yaml, sys
docs = list(yaml.safe_load_all(open("${F}")))
kinds = sorted([d['kind'] for d in docs if d])
assert kinds == ['Deployment', 'Namespace', 'Service'], f"kinds mismatch: {kinds}"
ns = [d for d in docs if d['kind']=='Namespace'][0]
assert ns['metadata']['name'] == 'flask-app'
dep = [d for d in docs if d['kind']=='Deployment'][0]
c = dep['spec']['template']['spec']['containers'][0]
assert 'gasbugs21c/my-flask-app' in c['image'], f"unexpected image: {c['image']}"
env_names = {e['name'] for e in c['env']}
assert 'OTEL_EXPORTER_OTLP_ENDPOINT' in env_names
svc = [d for d in docs if d['kind']=='Service'][0]
assert svc['spec']['type'] == 'LoadBalancer'
assert svc['spec']['ports'][0]['port'] == 80
assert svc['spec']['ports'][0]['targetPort'] == 5000
print("OK")
PY
if [ $? -eq 0 ]; then echo "PASS: 구조 검증 (ns/deploy/svc, 이미지, OTEL env, LB 포트)"; else echo "FAIL: 구조 검증"; fail=1; fi

if [ "${fail}" -eq 0 ]; then
  echo "==== feat-005 PASS ===="
  exit 0
else
  echo "==== feat-005 FAIL ===="
  exit 1
fi
