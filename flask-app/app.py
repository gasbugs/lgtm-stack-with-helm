"""
flask-app — OTel-instrumented Flask demo for LGTM stack.

개선 사항(원본 대비):
- 중복 import 제거 및 정리
- /to_stack 엔드포인트 추가 (트래픽 제너레이터가 호출하지만 원본에 없었음)
- /random_status가 실제로 무작위 4xx/5xx/2xx 응답 반환
- /error_test에서 현재 span에 exception을 기록(record_exception) + status=ERROR
- 모든 엔드포인트에 request_duration 히스토그램 자동 기록 (before/after_request 훅)
- endpoint 라벨을 메트릭/로그에서 일관되게 표기
- service.version, deployment.environment 등 리소스 속성 추가
- gunicorn 사용 (멀티 워커, 프로덕션 그레이드)
- 외부 API 호출에 타임아웃 + 실패 시 graceful fallback + span attr 기록
- 구조화 로깅(LOG_JSON=1 시 JSON)
- SIGTERM 처리 — BatchSpan/LogProcessor flush 후 종료
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import signal
import sys
import time
from functools import wraps

import requests
from flask import Flask, jsonify, request

from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import Status, StatusCode

# ── 설정 ──────────────────────────────────────────────────────────
OTLP_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://otel-collector-opentelemetry-collector.otel.svc.cluster.local:4317",
)
SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "flask-demo-service")
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "2.0.0")
DEPLOY_ENV = os.getenv("DEPLOY_ENV", "demo")
LOG_JSON = os.getenv("LOG_JSON", "0") == "1"

resource = Resource.create({
    "service.name": SERVICE_NAME,
    "service.version": SERVICE_VERSION,
    "service.namespace": os.getenv("POD_NAMESPACE", "flask-app"),
    "deployment.environment": DEPLOY_ENV,
    "k8s.pod.name": os.getenv("POD_NAME", ""),
    "k8s.node.name": os.getenv("NODE_NAME", ""),
})

# ── OTel: Traces ──────────────────────────────────────────────────
trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT))
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer(__name__)

# ── OTel: Logs ────────────────────────────────────────────────────
logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint=OTLP_ENDPOINT))
)
set_logger_provider(logger_provider)

# ── OTel: Metrics ─────────────────────────────────────────────────
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=OTLP_ENDPOINT)
)
metric_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(metric_provider)
meter = metrics.get_meter(__name__)

request_counter = meter.create_counter(
    name="http_request_count",
    description="Number of HTTP requests per endpoint",
    unit="1",
)
request_duration = meter.create_histogram(
    name="http_request_duration",
    description="Duration of HTTP requests in milliseconds",
    unit="ms",
)
in_flight = meter.create_up_down_counter(
    name="http_requests_in_flight",
    description="Concurrent in-flight requests",
    unit="1",
)
error_counter = meter.create_counter(
    name="http_request_errors",
    description="Application-level errors raised inside handlers",
    unit="1",
)

# ── 로깅 ──────────────────────────────────────────────────────────
class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(record.created)),
            "level": record.levelname,
            "msg": record.getMessage(),
            "logger": record.name,
            "trace_id": getattr(record, "otelTraceID", None),
            "span_id": getattr(record, "otelSpanID", None),
        }
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)
handler_stdout = logging.StreamHandler(sys.stdout)
if LOG_JSON:
    handler_stdout.setFormatter(JsonFormatter())
else:
    handler_stdout.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s [trace=%(otelTraceID)s span=%(otelSpanID)s] %(message)s")
    )
root_logger.addHandler(handler_stdout)
root_logger.addHandler(LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider))
LoggingInstrumentor().instrument(set_logging_format=False)
logger = logging.getLogger(__name__)

# ── Flask 앱 ─────────────────────────────────────────────────────
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="/health,/metrics")
RequestsInstrumentor().instrument()


@app.before_request
def _before_request() -> None:
    request._t0 = time.perf_counter()
    in_flight.add(1, {"endpoint": request.path})


@app.after_request
def _after_request(response):
    t0 = getattr(request, "_t0", None)
    endpoint = request.path
    if t0 is not None:
        duration_ms = (time.perf_counter() - t0) * 1000.0
        labels = {
            "endpoint": endpoint,
            "method": request.method,
            "status_code": str(response.status_code),
        }
        request_counter.add(1, labels)
        request_duration.record(duration_ms, labels)
    in_flight.add(-1, {"endpoint": endpoint})
    return response


@app.errorhandler(Exception)
def _handle_unexpected(exc: Exception):
    span = trace.get_current_span()
    span.record_exception(exc)
    span.set_status(Status(StatusCode.ERROR, str(exc)))
    error_counter.add(1, {"endpoint": request.path, "type": type(exc).__name__})
    logger.exception("Unhandled exception in handler")
    return jsonify({"error": type(exc).__name__, "message": str(exc)}), 500


# ── 엔드포인트 ───────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"message": "I'm healthy"}


@app.get("/")
def read_root():
    logger.info("Hello World")
    return {"Hello": "World"}


@app.get("/io_task")
def io_task():
    time.sleep(1)
    logger.info("io task completed")
    return "IO bound task finish!"


@app.get("/to_stack")
def to_stack():
    """Original repo's traffic_gen called /to_stack — generate a small synthetic call stack."""
    with tracer.start_as_current_span("stack_level_1") as s1:
        s1.set_attribute("level", 1)
        with tracer.start_as_current_span("stack_level_2") as s2:
            s2.set_attribute("level", 2)
            with tracer.start_as_current_span("stack_level_3") as s3:
                s3.set_attribute("level", 3)
                time.sleep(random.uniform(0.01, 0.05))
    logger.info("to_stack completed")
    return {"message": "stacked"}


@app.get("/cpu_task")
def cpu_task():
    with tracer.start_as_current_span("cpu_burn") as s:
        n = 0
        for i in range(200_000):
            n += i * i
        s.set_attribute("loops", 200_000)
    logger.info("cpu task completed")
    return {"result": "CPU bound task finish!"}


@app.get("/random_status")
def random_status():
    """Return a random 2xx / 4xx / 5xx response with weighted probability."""
    codes = [200, 200, 200, 201, 204, 400, 401, 403, 404, 500, 502, 503]
    code = random.choice(codes)
    if code >= 500:
        logger.error("random_status produced %s", code)
    elif code >= 400:
        logger.warning("random_status produced %s", code)
    else:
        logger.info("random_status produced %s", code)
    return jsonify({"path": "/random_status", "code": code}), code


@app.get("/random_sleep")
def random_sleep():
    delay = random.uniform(0, 2)
    span = trace.get_current_span()
    span.set_attribute("sleep.seconds", delay)
    time.sleep(delay)
    logger.info("random_sleep delay=%.2fs", delay)
    return {"path": "/random_sleep", "delay": round(delay, 2)}


@app.get("/error_test")
def error_test():
    logger.error("error_test triggered — raising ValueError")
    raise ValueError("intentional value error for tracing demo")


# ── 비동기 + 복합 트레이스 데모 ─────────────────────────────────
def async_action(f):
    @wraps(f)
    def wrapped(*args, **kwargs):
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            return loop.run_until_complete(f(*args, **kwargs))
        finally:
            loop.close()
    return wrapped


async def _async_task(name: str) -> None:
    with tracer.start_as_current_span(f"async_{name}") as span:
        delay = random.uniform(0.05, 0.3)
        span.set_attribute("task.delay", delay)
        await asyncio.sleep(delay)
        logger.info("Async task %s done in %.2fs", name, delay)


def _external_api_call(url: str) -> dict:
    with tracer.start_as_current_span("external_api_call") as span:
        span.set_attribute("http.url", url)
        try:
            resp = requests.get(url, timeout=2.0)
            span.set_attribute("http.status_code", resp.status_code)
            return resp.json()
        except (requests.RequestException, ValueError) as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, "external_api_failed"))
            logger.warning("External API failed: %s — returning fallback", exc)
            return {"fallback": True, "error": type(exc).__name__}


@app.route("/complex-operation")
@async_action
async def complex_operation():
    with tracer.start_as_current_span("complex_operation") as root_span:
        root_span.set_attribute("operation.type", "demo")
        logger.info("Starting complex operation")

        with tracer.start_as_current_span("database_query"):
            await asyncio.sleep(random.uniform(0.1, 0.3))
            logger.info("DB query done")

        with tracer.start_as_current_span("processing"):
            await asyncio.sleep(random.uniform(0.2, 0.4))
            logger.info("Data processing done")

        await asyncio.gather(
            _async_task("task1"),
            _async_task("task2"),
            _async_task("task3"),
        )

        external = _external_api_call("https://jsonplaceholder.typicode.com/todos/1")

        with tracer.start_as_current_span("final_computation"):
            await asyncio.sleep(random.uniform(0.05, 0.15))

        return {"message": "complex operation completed", "external": external}


# ── 시그널 처리: BatchProcessor flush ────────────────────────────
def _shutdown(signum, _frame):
    logger.info("Received signal %s — flushing OTel processors", signum)
    try:
        trace_provider.shutdown()
    except Exception:  # noqa: BLE001
        pass
    try:
        logger_provider.shutdown()
    except Exception:  # noqa: BLE001
        pass
    try:
        metric_provider.shutdown()
    except Exception:  # noqa: BLE001
        pass
    sys.exit(0)


signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)


if __name__ == "__main__":
    logger.info("Application started (dev mode)")
    app.run(debug=False, port=5000, host="0.0.0.0")
