package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// serviceName is the logical name reported to the OTel Collector / Datadog.
const serviceName = "evaluation-service"

// initOTel wires up the OpenTelemetry SDK (traces + metrics) exporting OTLP
// over gRPC to the OTel Collector (OTEL_EXPORTER_OTLP_ENDPOINT). If unset, the
// service runs uninstrumented. Returns a shutdown func that flushes exporters.
func initOTel(ctx context.Context) (func(context.Context) error, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT not set — telemetry disabled")
		return func(context.Context) error { return nil }, nil
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(os.Getenv("SERVICE_VERSION")),
			semconv.DeploymentEnvironment(envOrDefault("DEPLOY_ENV", "prod")),
		),
		resource.WithFromEnv(),
		resource.WithProcess(),
	)
	if err != nil {
		return nil, err
	}

	traceExp, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	metricExp, err := otlpmetricgrpc.New(ctx)
	if err != nil {
		return nil, err
	}
	mp := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(metricExp,
			metric.WithInterval(15*time.Second))),
	)
	otel.SetMeterProvider(mp)

	// ── Logs ──
	// Export application logs via OTLP/gRPC to the Collector → Loki, using the
	// same OTEL_EXPORTER_OTLP_ENDPOINT as traces/metrics.
	logExp, err := otlploggrpc.New(ctx)
	if err != nil {
		return nil, err
	}
	lp := sdklog.NewLoggerProvider(
		sdklog.WithResource(res),
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)),
	)

	// Bridge the stdlib `log` package onto OTel: emit one OTLP log record per
	// line via the OTel log API, while still printing to stdout for kubectl.
	log.SetOutput(otelLogWriter{logger: lp.Logger(serviceName)})
	log.SetFlags(0)

	log.Printf("OpenTelemetry initialized (service=%s, endpoint=%s)", serviceName, endpoint)

	return func(ctx context.Context) error {
		return errors.Join(tp.Shutdown(ctx), mp.Shutdown(ctx), lp.Shutdown(ctx))
	}, nil
}

// otelLogWriter adapts the OTel log API to an io.Writer so the stdlib `log`
// package output is emitted as OTLP log records (→ Collector → Loki) while
// still writing to stdout for kubectl logs.
type otelLogWriter struct {
	logger otellog.Logger
}

func (w otelLogWriter) Write(p []byte) (int, error) {
	msg := strings.TrimRight(string(p), "\n")
	var rec otellog.Record
	rec.SetTimestamp(time.Now())
	rec.SetSeverity(otellog.SeverityInfo)
	rec.SetBody(attribute.StringValue(msg))
	w.logger.Emit(context.Background(), rec)
	_, _ = os.Stdout.Write(p)
	return len(p), nil
}

// otelHandler wraps an http.Handler so every incoming request is traced.
func otelHandler(h http.Handler) http.Handler {
	return otelhttp.NewHandler(h, "http.server")
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
