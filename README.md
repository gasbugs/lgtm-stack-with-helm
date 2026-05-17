# lgtm-stack-with-helm

쿠버네티스 + OpenTelemetry Collector + LGTM 스택(Loki·Grafana·Tempo·Mimir) 통합 관측성 실습 환경을 **한 줄로** 배포합니다.

## 한 줄 배포

### A. GKE 자동 생성 + 전체 배포
```bash
CREATE_GKE=1 bash deploy.sh
```
fsi* GCP 프로젝트에 `lgtm-cluster` (us-central1-a, e2-standard-4 × 3) 생성 → LGTM → OTel Collector → Flask 앱 → 트래픽 제너레이터까지 자동 배포.

### B. 이미 클러스터가 있는 경우
```bash
bash deploy.sh
```

### C. 명령어만 확인하고 싶을 때
```bash
DRY_RUN=1 bash deploy.sh
```

배포가 끝나면 마지막 출력에 Grafana / 대시보드 / Flask 앱 외부 IP가 표시됩니다.
- Grafana: `admin / Test1234`
- 대시보드 자동 등록: **Flask App — Observability (LGTM)**

## 정리

앱·LGTM·OTel만 삭제(클러스터는 유지):
```bash
bash cleanup.sh
```

클러스터까지 삭제:
```bash
gcloud container clusters delete lgtm-cluster --zone=us-central1-a --project=<fsi-project>
```

## 디렉터리 구조
```
.
├── deploy.sh                # 한 줄 배포 진입점
├── cleanup.sh               # 한 줄 정리
├── init.sh                  # 하네스 초기화 래퍼
├── scripts/
│   ├── create-gke.sh        # GKE 클러스터 생성
│   ├── 00-prereq.sh         # 도구 확인
│   ├── 01-repos.sh          # helm repo + ns
│   ├── 02-lgtm.sh           # Loki + Tempo + kube-prometheus-stack
│   ├── 03-otel.sh           # OTel Collector
│   ├── 04-datasources.sh    # Grafana DataSource + Dashboard ConfigMap
│   ├── 05-flask-app.sh      # Flask 앱
│   ├── 06-traffic.sh        # 트래픽 제너레이터(백그라운드)
│   └── traffic_gen.sh       # 트래픽 루프
├── values/                  # Helm values 파일
│   ├── loki-values.yaml
│   ├── tempo-values.yaml
│   ├── kube-prom-values.yaml
│   └── otel-values.yaml
├── manifests/
│   ├── flask-app.yaml          # ns + deployment + LoadBalancer
│   ├── grafana-datasources.yaml # sidecar 자동 로드 (Loki/Tempo)
│   └── flask-dashboard.yaml    # sidecar 자동 로드 대시보드
├── flask-app/                  # OTel-instrumented Flask 데모 소스
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
└── tests/e2e/                  # feature 단위 + 통합 E2E
    └── test_full.sh
```

## 컨테이너 이미지

`docker.io/gasbugs21c/my-flask-app:lgtm-v2` — 멀티아키(linux/amd64, linux/arm64)

소스를 변경한 뒤 다시 빌드/푸시하려면:
```bash
podman manifest create docker.io/gasbugs21c/my-flask-app:lgtm-v2
podman build --platform=linux/amd64,linux/arm64 \
  --manifest docker.io/gasbugs21c/my-flask-app:lgtm-v2 flask-app/
podman manifest push --all docker.io/gasbugs21c/my-flask-app:lgtm-v2 \
  docker://docker.io/gasbugs21c/my-flask-app:lgtm-v2
```

## E2E 테스트
```bash
bash tests/e2e/test_full.sh
```
helm template 렌더링, YAML 구조, deploy/cleanup DRY_RUN 등 오프라인 검증만 수행 — 실제 클러스터가 없어도 통과.
