# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Kubernetes(GKE 또는 kind) + OpenTelemetry Collector + LGTM 스택(Loki·Grafana·Tempo·Prometheus) + 선택적으로 Cilium(CNI/Hubble)을 **한 줄 명령**으로 배포하는 통합 관측성 실습 환경. 모든 단계가 멱등(`helm upgrade --install`, `kubectl apply`)하고 `DRY_RUN=1`로 안전 점검 가능.

## 자주 쓰는 명령

```bash
# zero-state 자동화 진입점
CREATE_GKE=1 bash deploy.sh                    # GKE 신규 + 기본 흐름
USE_KIND=1 bash deploy.sh                      # kind + metallb + kube-proxy
USE_KIND=1 WITH_CILIUM=1 bash deploy.sh        # kind + cilium(kubeProxyReplacement) + Hubble
DRY_RUN=1 USE_KIND=1 WITH_CILIUM=1 bash deploy.sh   # 명령 echo만

# 정리
bash cleanup.sh                # 앱·LGTM·OTel 제거 (클러스터/네트워킹 유지)
bash cleanup.sh --kind-addons  # kind 전용 cilium·metallb까지 함께 제거
bash cleanup.sh --delete-kind  # kind 클러스터 통째로 삭제
gcloud container clusters delete lgtm-cluster --zone=us-central1-a --project=<fsi>  # GKE 삭제

# 통합 E2E (오프라인 — 클러스터 없어도 통과)
bash tests/e2e/test_full.sh
bash tests/e2e/test_feat-<NNN>.sh        # 개별

# Flask 이미지 재빌드 (멀티아키 → Docker Hub)
IMG=docker.io/gasbugs21c/my-flask-app:lgtm-v2
podman manifest rm "$IMG" 2>/dev/null
podman manifest create "$IMG"
podman build --platform=linux/amd64,linux/arm64 --manifest "$IMG" flask-app/
podman manifest push --all "$IMG" "docker://$IMG"
```

## 단계별 스크립트 흐름 (옵션별)

| 환경 변수 | 추가되는 단계 |
|---|---|
| `CREATE_GKE=1` | `create-gke.sh` (0단계) |
| `USE_KIND=1` | `create-kind.sh` (0단계) → `01b-metallb.sh` → `03b-otel-agent.sh` |
| `WITH_CILIUM=1` | `01c-cilium.sh` (CNI만, metallb 앞) → `02b-cilium-metrics.sh` (LGTM 뒤, ServiceMonitor 활성화) |

**중요한 순서 제약**: cilium은 CNI라 노드가 Ready되려면 먼저 깔려야 함 (metallb 컨트롤러가 schedule되려면 노드 Ready 필요). cilium은 2단계로 분리되어 있는데 ServiceMonitor 리소스 자체가 prometheus-operator CRD 의존이라 LGTM 설치 후에야 활성화 가능.

## 아키텍처 핵심

**데이터 흐름**: Flask 앱(OTel SDK) → OTel Collector (deployment) → 3-way fanout
- logs → Loki gateway
- metrics → Prometheus remote-write
- traces → Tempo distributor (OTLP gRPC)

**kind 환경 추가 흐름**: OTel Collector DaemonSet (`scripts/03b`)이 각 노드에서
- `filelog` receiver — `/var/log/pods/*/*/*.log` → Loki
- `hostmetrics` receiver — system CPU/mem/disk/network → Prometheus
- `kubeletstats` receiver — `:10250` → k8s_pod_*, k8s_volume_* → Prometheus

**Grafana sidecar**: ConfigMap을 라벨로 자동 로드 — DataSource/Dashboard 모두 코드로 관리
- `manifests/grafana-datasources.yaml` (`grafana_datasource=1`) — Loki UID `loki` 명시 필수
- `manifests/flask-dashboard.yaml`, `manifests/k8s-system-dashboard.yaml` (`grafana_dashboard=1`)

**04-datasources.sh 자기 복구**: 재배포 시 sidecar가 만든 임의 Loki UID(예: `P8E80F9AEF21F6940`)를 발견하면 API로 삭제하고 sidecar에게 재생성 시키는 로직 내장.

## kind 환경 함정 모음

이 프로젝트에서 발견된 함정들 — 같은 실수 반복 금지:

1. **kind docker network에 IPv4와 IPv6 둘 다**: MetalLB IPAddressPool은 IPv4만 받음. `docker network inspect kind --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' | grep -v ':' | head -1` 패턴 사용.

2. **kubelet self-signed cert**: OTel `kubeletstats` receiver는 TLS 검증함 → `insecure_skip_verify: true` 명시 필요 (preset만으로는 안 됨).

3. **컨트롤 플레인 메트릭 노출**: kind는 controller-manager/scheduler/etcd가 기본 `127.0.0.1` 바인딩 → `kind/cluster.yaml`의 `kubeadmConfigPatches`에서 `bind-address: 0.0.0.0`, etcd `listen-metrics-urls: http://0.0.0.0:2381`로 변경. 또한 `kubeProxyMode: none` + cilium이면 `kube-proxy ServiceMonitor` 비활성화 (`kubeProxy.enabled=false`).

4. **외부 차트의 ServiceMonitor 픽업**: kube-prometheus-stack 기본 selector는 `release` 라벨 매칭만. 외부 차트(cilium 등)가 만든 ServiceMonitor는 무시됨. `kube-prom-values.kind.yaml`의 `serviceMonitorSelectorNilUsesHelmValues: false` + 빈 selector로 모든 ServiceMonitor/PodMonitor/Rule 픽업.

5. **cilium chart 설치 시 ServiceMonitor 검증**: `trustCRDsExist=true`는 사전 validation만 우회, 실제 객체 생성에는 CRD 필요 → 2단계 설치(`01c` CNI만, `02b` ServiceMonitor 활성화).

6. **MetalLB가 부여한 IP는 docker network 내부 주소**: 호스트(VM) 안에서는 직접 접근 가능. VM 밖(인터넷)에서는 `socat`으로 호스트 포트 → metallb IP로 포워딩. 80/8080 포트가 깔끔(30080은 kind extraPortMappings와 충돌).

## Loki 라벨 규칙

OTel Collector의 loki exporter는 `service.namespace` + `service.name`을 합쳐 `service_name="<ns>/<svc>"` 형태로 라벨링. `namespace` 라벨은 **만들지 않음**.

```
{service_name=~".+/$service|$service"}     # 앱 로그 (Flask, monitoring 등)
{service_name=~"kube-system/.+"}           # kube-system 컨테이너 로그
```

## OTel 에서 들어오는 메트릭 이름 (Prometheus 측)

prometheusremotewrite exporter가 dot을 underscore로 변환:
- **hostmetrics**: `system_cpu_load_average_{1m,5m,15m}`, `system_memory_usage_bytes`, `system_disk_io_bytes_total`, `system_network_io_bytes_total`, `system_filesystem_usage_bytes`
- **kubeletstats**: `k8s_pod_cpu_usage`, `k8s_pod_memory_working_set_bytes`, `k8s_pod_network_io_bytes_total`, `k8s_volume_capacity_bytes`, `k8s_volume_available_bytes`
- `k8s_node_*` 는 거의 비어있고 host 메트릭은 `system_*` 쪽에 들어옴 (label: `host_name`)

## 컨테이너 이미지

`docker.io/gasbugs21c/my-flask-app:lgtm-v2` (linux/amd64 + linux/arm64). **AR(us-central1-docker.pkg.dev/...)는 폐기됨** — 사용 금지.

## 하네스 규칙 (전역 CLAUDE.md에서 상속됨)

이 프로젝트는 `~/my-harness` 하네스로 관리됨. 세션 시작 시:
1. `bash init.sh` (프로젝트 로컬 래퍼 — `my-harness/init.sh`로 위임)
2. `claude-progress.txt`, `feature-list.json`, `git log --oneline -10` 확인

**`feature-list.json` 보호 필드** — 절대 수정 금지: `id`, `name`, `description`, `notes`, **객체 추가/삭제 모두 금지**. `passes`만 변경 가능. `mv/cp`로 덮어쓰기는 `bash-guard` 훅이 차단. 변경은 `Edit` 도구로.

**커밋 형식** (모든 커밋 필수):
```
<타입>(<범위>): <제목>

Feature: <feat-NNN 또는 docs/fix>
Tests: <passed|not-applicable>
Progress: <한 줄 요약>
```

## 검증 전략

`tests/e2e/test_full.sh`는 **실제 클러스터 없이도 통과**해야 함:
- `helm template <chart> -f values/<v>.yaml` 렌더링
- YAML 구조를 `python3 yaml`로 파싱·검증 (kubectl `--validate=true`는 API 서버 필요해 사용 금지)
- `DRY_RUN=1 bash deploy.sh` 출력에 핵심 helm/kubectl 명령이 포함되는지 grep

새 feature 추가 시 같은 패턴으로 `tests/e2e/test_feat-<NNN>.sh`를 만들고 `test_full.sh`의 `tests` 배열에 추가.

## 외부 의존성

- GCP 프로젝트: `fsi*` (gcloud `projects list --filter='projectId:fsi*'`의 첫 번째 매칭)
- Docker Hub: `gasbugs21c` 계정
- 원본 강의 저장소(아카이브됨): `github.com/gasbugs/lgtm-k8s`, `github.com/gasbugs/lgtm-docker`
- 테스트 SpotVM (있을 수도, 없을 수도): `lgtm-spot` (us-central1-a)
