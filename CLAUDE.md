# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

GKE(Kubernetes) + OpenTelemetry Collector + LGTM 스택(Loki·Grafana·Tempo·Prometheus)을 **한 줄 명령**으로 배포하는 통합 관측성 실습 환경. 모든 단계가 멱등(`helm upgrade --install`, `kubectl apply`)하고 `DRY_RUN=1`로 안전 점검 가능.

## 자주 쓰는 명령

| 작업 | 명령 |
|---|---|
| GKE 자동 생성 + 전체 배포 (zero-state) | `CREATE_GKE=1 bash deploy.sh` |
| 기존 클러스터에 배포 | `bash deploy.sh` |
| 명령어만 출력 (dry-run) | `DRY_RUN=1 bash deploy.sh` |
| 앱·LGTM·OTel 제거 (클러스터 유지) | `bash cleanup.sh` |
| 클러스터까지 제거 | `gcloud container clusters delete lgtm-cluster --zone=us-central1-a --project=<fsi-project>` |
| 통합 E2E (오프라인) | `bash tests/e2e/test_full.sh` |
| 개별 feature 테스트 | `bash tests/e2e/test_feat-<NNN>.sh` |
| Flask 이미지 멀티아키 빌드/푸시 | `podman manifest create $IMG && podman build --platform=linux/amd64,linux/arm64 --manifest $IMG flask-app/ && podman manifest push --all $IMG docker://$IMG` |

(`$IMG = docker.io/gasbugs21c/my-flask-app:lgtm-v2`)

## 아키텍처 핵심

**데이터 흐름**: Flask 앱(OTel SDK) ──OTLP:4317──▶ OTel Collector ──▶ 3-way fanout
- logs → Loki gateway
- metrics → Prometheus remote-write
- traces → Tempo distributor (OTLP gRPC)

Grafana는 sidecar가 ConfigMap을 라벨로 자동 로드 — **DataSource·Dashboard 모두 코드로 관리**:
- `manifests/grafana-datasources.yaml` (label `grafana_datasource=1`) — Loki/Tempo UID 명시
- `manifests/flask-dashboard.yaml` (label `grafana_dashboard=1`)

**배포 오케스트레이션**: `deploy.sh`가 `scripts/<NN>-*.sh`를 순서대로 실행. `CREATE_GKE=1`이면 `create-gke.sh`가 0단계로 추가됨. 각 스크립트는 `DRY_RUN=1`에서 명령만 echo.

**04-datasources.sh의 자기 복구**: Grafana sidecar가 `uid` 명시 없이 만든 랜덤 UID Loki datasource를 발견하면 API로 삭제하고 sidecar에게 재생성 시키는 로직 내장. README의 트러블슈팅 항목 참고.

## Loki 라벨 주의사항

OTel Collector의 loki exporter는 `service.namespace` + `service.name`을 합쳐서 라벨링한다 — 즉 `service_name="flask-app/flask-demo-service"` 형태로 들어옴.
대시보드와 모든 LogQL 쿼리는 다음 정규식 매칭을 사용:
```
{service_name=~".+/$service|$service"}
```
새 LogQL을 추가할 때 이 규칙을 따를 것.

## 컨테이너 이미지

`docker.io/gasbugs21c/my-flask-app:lgtm-v2` (linux/amd64 + linux/arm64 멀티아키).
**중간에 Artifact Registry로 푸시한 흔적은 폐기됨** — `manifests/flask-app.yaml`의 image는 Docker Hub만 가리킴. Cloud Build 경로(`us-central1-docker.pkg.dev/...`)는 사용 금지.

## 하네스 규칙 (전역 CLAUDE.md에서 상속됨)

이 프로젝트는 `~/my-harness` 하네스로 관리됨. 세션 시작 시 반드시:
1. `bash init.sh` (프로젝트 로컬 래퍼 — `my-harness/init.sh`로 위임)
2. `claude-progress.txt`, `feature-list.json`, `git log --oneline -10` 확인

**`feature-list.json` 보호 필드** — 절대 수정 금지: `id`, `name`, `description`, `notes`. `passes` 필드만 변경 가능하며, 다음 5가지 충족 시에만 `true`:
- 구현 완료 / E2E 테스트 작성 / 테스트 종료코드 0 / `claude-progress.txt`에 증거 기록 / 구현+테스트 함께 커밋

**커밋 형식** (모든 커밋 필수):
```
<타입>(<범위>): <제목>

Feature: <feat-NNN>
Tests: <passed|not-applicable>
Progress: <한 줄 요약>
```

## 검증 전략

`tests/e2e/test_full.sh`는 **실제 클러스터 없이도 통과**해야 함:
- `helm template <chart> -f values/<v>.yaml` 렌더링
- YAML 구조를 `python3 yaml`로 파싱·검증 (kubectl --validate=true는 API 서버 필요해 사용 금지)
- `DRY_RUN=1` 실행 출력에 핵심 helm/kubectl 명령이 포함되는지 grep

새 feature 추가 시 같은 패턴으로 `tests/e2e/test_feat-<NNN>.sh`를 만들고 `test_full.sh`의 `tests` 배열에 추가할 것.

## 외부 의존성

- GCP 프로젝트: `fsi*` (gcloud `projects list --filter='projectId:fsi*'`의 첫 번째 매칭)
- Docker Hub: `gasbugs21c` 계정 (이미지 푸시 시)
- 원본 강의 저장소(아카이브됨): `github.com/gasbugs/lgtm-k8s`, `github.com/gasbugs/lgtm-docker`
