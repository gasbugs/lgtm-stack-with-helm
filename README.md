# lgtm-stack-with-helm

> Kubernetes(GKE) + OpenTelemetry Collector + **LGTM 스택**(Loki·Grafana·Tempo·Prometheus)을
> **한 줄 명령으로** 배포하는 통합 관측성(Observability) 실습 환경.

---

## 한눈에 보기

| 영역 | 도구 | 포트/엔드포인트 |
|---|---|---|
| **메트릭** | Prometheus (kube-prometheus-stack) | `:9090` (in-cluster) |
| **로그**   | Loki (SingleBinary) | `:3100` / gateway `:80` |
| **트레이스** | Tempo (distributed) | `:3200` / OTLP `:4317` |
| **시각화** | Grafana | LoadBalancer `:80` |
| **수집기** | OpenTelemetry Collector (deployment) | OTLP `:4317`/`:4318` |
| **데모 앱** | Flask + OTel SDK | LoadBalancer `:80` → `:5000` |

---

## 아키텍처

```
   ┌──────────────┐         ┌───────────────────────┐
   │  Flask App   │  OTLP   │ OpenTelemetry         │
   │  + OTel SDK  │ ──────▶ │ Collector (deployment)│
   │  (logs/      │  :4317  │                       │
   │   metrics/   │         │  pipelines:           │
   │   traces)    │         │   logs    → Loki      │
   └──────────────┘         │   metrics → Prometheus│
          ▲                 │   traces  → Tempo     │
          │ traffic_gen.sh  └─────────┬─────────────┘
          │                           │
   ┌──────┴─────────────┐             ▼
   │ LoadBalancer (k8s) │     ┌──────────────────────┐
   └────────────────────┘     │   Loki  Tempo  Prom  │
                              │       └─┬──┘         │
                              │         ▼            │
                              │      Grafana ◀── LB  │ ← 사용자 브라우저
                              │     (자동 등록된      │
                              │      DataSources +   │
                              │      대시보드)        │
                              └──────────────────────┘
```

**핵심 흐름**: 앱의 신호(log/metric/trace) → OTel Collector → 백엔드 분기 → Grafana에서 단일 화면으로 조회.

---

## 사전 요구사항

| 필수 | 용도 |
|---|---|
| `gcloud` (인증 완료) | GKE 자동 생성 옵션 사용 시 |
| `kubectl` ≥ 1.28 | k8s 리소스 적용 |
| `helm` ≥ 3.14 | 차트 설치 |
| `jq` | 스크립트 보조 |
| `bash` ≥ 4 | 스크립트 실행 |

> `CREATE_GKE=1` 옵션을 안 쓰면 이미 접근 가능한 어떤 쿠버네티스 클러스터든 OK (kind/minikube/EKS 등).

---

## 한 줄 배포

```bash
# A. GKE 자동 생성 + 전체 배포 (gcloud fsi* 프로젝트 자동 선택)
CREATE_GKE=1 bash deploy.sh

# B. 이미 있는 클러스터에 배포
bash deploy.sh

# C. 명령어만 출력 (안전 점검)
DRY_RUN=1 bash deploy.sh
```

배포가 끝나면 마지막에 외부 IP가 출력됩니다:

```
════════════════════════════════════════════════════════
  배포 완료
════════════════════════════════════════════════════════
  Grafana   : http://34.132.168.28   (admin / Test1234)
  대시보드  : http://34.132.168.28/d/flask-app-observability
  Flask App : http://34.173.116.177
════════════════════════════════════════════════════════
```

---

## 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `CREATE_GKE` | `0` | `1`이면 GKE 클러스터를 먼저 생성 |
| `GKE_CLUSTER` | `lgtm-cluster` | (create-gke.sh 인자) |
| `GKE_ZONE` | `us-central1-a` | (create-gke.sh 인자) |
| `DRY_RUN` | `0` | `1`이면 실제 실행 없이 명령만 출력 |

---

## 미리 만들어둔 Grafana 대시보드

**Flask App — Observability (LGTM)** — Grafana sidecar가 ConfigMap을 자동 로드합니다.

- 상단 KPI: 총 요청 수, RPS, 5xx 에러율, P95 지연, Pod Up 여부
- RPS by Endpoint (스택 영역 그래프)
- HTTP Status (2xx/4xx/5xx 색상 구분)
- P50 / P95 / P99 Latency
- Top Endpoints (15분, Bar gauge)
- Pod CPU / Memory
- **Loki 라이브 로그** — LogQL `json | line_format` 으로 `[LEVEL] (logger) msg trace_id=...` 형식
- **Tempo 최근 트레이스** — traceqlSearch 결과 테이블, traceID 클릭 → 트레이스 상세

대시보드 변수:
- `$service` (Prometheus `label_values(http_request_count_total, service_name)`)
- `$endpoint` (선택된 service의 endpoint 목록, multi)

---

## 디렉터리 구조

```
.
├── deploy.sh                # ⭐ 한 줄 배포 진입점
├── cleanup.sh               # 한 줄 정리
├── init.sh                  # 하네스 초기화 래퍼
├── README.md
│
├── scripts/                 # 배포 단계별 스크립트
│   ├── create-gke.sh        # GKE 클러스터 생성 (CREATE_GKE=1일 때)
│   ├── 00-prereq.sh         # 도구 확인
│   ├── 01-repos.sh          # helm repo + 네임스페이스
│   ├── 02-lgtm.sh           # Loki + Tempo + kube-prometheus-stack
│   ├── 03-otel.sh           # OTel Collector
│   ├── 04-datasources.sh    # Grafana DataSource + Dashboard ConfigMap
│   ├── 05-flask-app.sh      # Flask 앱
│   ├── 06-traffic.sh        # 트래픽 제너레이터(백그라운드)
│   └── traffic_gen.sh       # 트래픽 루프 본체
│
├── values/                  # Helm values (모든 --set 인자를 파일로)
│   ├── loki-values.yaml
│   ├── tempo-values.yaml
│   ├── kube-prom-values.yaml
│   └── otel-values.yaml
│
├── manifests/
│   ├── flask-app.yaml           # ns + deployment + LoadBalancer + probes
│   ├── grafana-datasources.yaml # sidecar 자동 로드 (Loki/Tempo)
│   └── flask-dashboard.yaml     # sidecar 자동 로드 대시보드
│
├── flask-app/               # OTel-instrumented 데모 앱 소스
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── tests/e2e/               # feature 단위 + 통합 E2E 테스트
│   ├── test_feat-001.sh ... test_feat-008.sh
│   └── test_full.sh         # 통합 진입점
│
├── feature-list.json        # 하네스 진척 추적
└── claude-progress.txt      # 세션 로그 (.gitignore됨)
```

---

## 컴포넌트별 설명

### 1. LGTM 백엔드
| 컴포넌트 | 차트 | values |
|---|---|---|
| Loki (SingleBinary, 파일시스템) | `grafana/loki` | `values/loki-values.yaml` |
| Tempo (distributed) | `grafana-community/tempo-distributed` | `values/tempo-values.yaml` |
| Prometheus + Grafana | `prometheus-community/kube-prometheus-stack` | `values/kube-prom-values.yaml` |

`kube-prom-values.yaml`에는 **Grafana sidecar 활성화**가 들어 있어, label만 붙은 ConfigMap을 자동으로 DataSource·Dashboard로 로드합니다:
```yaml
grafana:
  sidecar:
    datasources: { enabled: true, label: grafana_datasource }
    dashboards:  { enabled: true, label: grafana_dashboard  }
```

### 2. OpenTelemetry Collector
`values/otel-values.yaml`에서 receiver/exporter/pipeline을 분리:
- `receivers: otlp` (gRPC :4317, HTTP :4318)
- `exporters`:
  - `loki` → `http://loki-gateway.monitoring:80/loki/api/v1/push`
  - `prometheusremotewrite` → kube-prometheus-stack의 remote-write
  - `otlp/tempo` → `tempo-distributor.monitoring:4317`
- pipelines: logs / metrics / traces 세 갈래 독립

### 3. Flask 데모 앱 (`flask-app/`)
원본 `gasbugs/lgtm-k8s/flask-app` 대비 개선:
- 중복 import 정리, `/to_stack` 신규(원본은 traffic_gen이 호출하지만 정의 없음)
- `/random_status`가 실제로 무작위 2xx/4xx/5xx 반환
- `/error_test`에서 `span.record_exception` + `Status(ERROR)` 기록
- 모든 엔드포인트에 `before/after_request` 훅으로 duration·in-flight·counter 자동 기록
- `LOG_JSON=1`이면 JSON 구조화 로그, SIGTERM에서 BatchProcessor flush
- resource attr 확장(`service.version`, `deployment.environment`, `k8s.pod.name`, `k8s.node.name`)
- **gunicorn**(2 workers × 4 threads), non-root user, HEALTHCHECK
- 외부 API 호출 타임아웃 + graceful fallback + span 속성 기록

### 4. 트래픽 제너레이터
`scripts/traffic_gen.sh` — 1초 간격으로 8개 엔드포인트에 무작위 요청.
`scripts/06-traffic.sh` — 배포 직후 백그라운드로 자동 실행 (PID 파일 + 로그 파일).

```bash
# 수동 실행
bash scripts/traffic_gen.sh http://<FLASK-IP>

# 중단
bash scripts/06-traffic.sh stop
```

---

## 컨테이너 이미지

`docker.io/gasbugs21c/my-flask-app:lgtm-v2` — **멀티아키**(linux/amd64, linux/arm64)

소스를 수정한 뒤 다시 빌드/푸시(podman 사용):
```bash
IMG=docker.io/gasbugs21c/my-flask-app:lgtm-v2

podman manifest rm "$IMG" 2>/dev/null || true
podman manifest create "$IMG"
podman build --platform=linux/amd64,linux/arm64 --manifest "$IMG" flask-app/
podman manifest push --all "$IMG" "docker://$IMG"
```

---

## 정리

앱·LGTM·OTel만 삭제 (클러스터는 유지):
```bash
bash cleanup.sh

# 네임스페이스를 살리고 싶다면
bash cleanup.sh --keep-ns
```

클러스터까지 삭제:
```bash
gcloud container clusters delete lgtm-cluster \
  --zone=us-central1-a --project=<fsi-project>
```

---

## 테스트 / 검증

오프라인 E2E (실제 클러스터 없어도 통과 — helm template 렌더링·YAML 구조·DRY_RUN 검증):
```bash
bash tests/e2e/test_full.sh
```

기대 출력:
```
요약: PASS 8개, FAIL 0개
==== ALL TESTS PASS ====
```

개별 feature 테스트:
```bash
bash tests/e2e/test_feat-002.sh   # LGTM values 렌더링
bash tests/e2e/test_feat-007.sh   # deploy.sh 오케스트레이터
```

---

## 트러블슈팅

### Grafana에서 로그/트레이스가 안 보임
1. `kubectl -n flask-app get pod` → Running 인지
2. `kubectl -n otel logs -l app.kubernetes.io/name=opentelemetry-collector` → error/warn 반복 없는지
3. Grafana → Explore → DataSource `Loki` 선택 → `{service_name=~".+/flask-demo-service|flask-demo-service"}` 실행
   - OTel loki exporter는 `service.namespace` + `service.name`을 합쳐 `flask-app/flask-demo-service` 형태로 라벨링하므로 정규식 매칭 필요
4. Tempo → Explore → TraceQL `{ resource.service.name="flask-demo-service" }`

### Loki DataSource UID가 랜덤
- 두 번째 이후 배포에서 `04-datasources.sh`가 자동 복구합니다 (잘못된 UID 삭제 후 sidecar 재생성).
- 수동 복구: `curl -u admin:Test1234 -X DELETE http://<GRAFANA-IP>/api/datasources/uid/<RANDOM_UID>`

### Flask 앱이 OTel Collector를 못 찾음
- `OTEL_EXPORTER_OTLP_ENDPOINT`가 `http://otel-collector-opentelemetry-collector.otel.svc.cluster.local:4317` 인지 확인
- Collector 서비스: `kubectl -n otel get svc`

### LoadBalancer EXTERNAL-IP가 `<pending>`
- GCP 외 환경에서 LB Controller가 없을 수 있음 → `port-forward`로 우회:
  ```bash
  kubectl -n monitoring port-forward svc/my-prom-grafana 3000:80
  ```

---

## 라이선스 / 출처

- 원본 강의: `https://github.com/gasbugs/lgtm-k8s` (아카이브)
- LGTM 스택: Grafana Labs 공식 차트
- OpenTelemetry: CNCF 프로젝트
