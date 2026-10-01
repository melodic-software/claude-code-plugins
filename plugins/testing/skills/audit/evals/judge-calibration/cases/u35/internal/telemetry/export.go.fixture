package telemetry

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	apiMetric "go.opentelemetry.io/otel/metric"
	metricnoop "go.opentelemetry.io/otel/metric/noop"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/semconv/v1.26.0"
	apiTrace "go.opentelemetry.io/otel/trace"
	tracenoop "go.opentelemetry.io/otel/trace/noop"
)

const (
	defaultMetricExportInterval = 60 * time.Second
	defaultMetricExportTimeout  = 30 * time.Second
)

type Options struct {
	HostID  string
	Version string
	OnError func(error)
	Export  *ExportConfig
}

// ExportConfig is the reviewed host configuration for OTLP export. When it is
// present, signal enablement, endpoint, protocol, and metric cadence come from
// the host YAML rather than ambient process environment.
type ExportConfig struct {
	Endpoint             string
	Protocol             string
	Traces               bool
	Metrics              bool
	MetricExportInterval time.Duration
	MetricExportTimeout  time.Duration
}

// Provider owns only the exporters that were explicitly enabled. An empty
// standard OTEL environment returns a no-op provider without dialing localhost.
type Provider struct {
	recorder Recorder
	shutdown []func(context.Context) error
	enabled  bool
}

func (p *Provider) BeginReconcile(ctx context.Context) (context.Context, func(ReconcileSnapshot, error)) {
	return p.recorder.BeginReconcile(ctx)
}
func (p *Provider) WorkerRegistered(ctx context.Context, poolID, tier string, duration time.Duration, outcome WorkerStartOutcome) {
	p.recorder.WorkerRegistered(ctx, poolID, tier, duration, outcome)
}
func (p *Provider) WorkerStarted(ctx context.Context, poolID, tier string, duration time.Duration, outcome WorkerStartOutcome) {
	p.recorder.WorkerStarted(ctx, poolID, tier, duration, outcome)
}
func (p *Provider) WorkerFinalized(ctx context.Context, poolID string, value WorkerFinalization) {
	p.recorder.WorkerFinalized(ctx, poolID, value)
}
func (p *Provider) ObserveJobStarted(ctx context.Context, poolID string, visibilityLag time.Duration) {
	p.recorder.ObserveJobStarted(ctx, poolID, visibilityLag)
}
func (p *Provider) ObserveJobCompleted(ctx context.Context, poolID, result string, assigned bool) {
	p.recorder.ObserveJobCompleted(ctx, poolID, result, assigned)
}

func (p *Provider) Shutdown(ctx context.Context) error {
	var errs []error
	for index := len(p.shutdown) - 1; index >= 0; index-- {
		errs = append(errs, p.shutdown[index](ctx))
	}
	return errors.Join(errs...)
}

func NewFromEnv(ctx context.Context, options Options) (*Provider, []error) {
	provider := &Provider{recorder: Noop()}
	if options.OnError == nil {
		options.OnError = func(error) {}
	}
	if options.HostID == "" || options.Version == "" {
		return provider, []error{errors.New("telemetry service identity requires host ID and version")}
	}
	var traceEnabled, metricEnabled bool
	var traceProtocol, metricProtocol, endpoint string
	metricInterval, metricTimeout := defaultMetricExportInterval, defaultMetricExportTimeout
	var problems []error
	if options.Export != nil {
		traceEnabled, metricEnabled = options.Export.Traces, options.Export.Metrics
		traceProtocol, metricProtocol = options.Export.Protocol, options.Export.Protocol
		endpoint = options.Export.Endpoint
		metricInterval, metricTimeout = options.Export.MetricExportInterval, options.Export.MetricExportTimeout
	} else {
		disabled, err := sdkDisabled(os.LookupEnv)
		if err != nil {
			return provider, []error{err}
		}
		if disabled {
			return provider, nil
		}
		var traceErr, metricErr error
		traceEnabled, traceErr = signalEnabled(os.LookupEnv, "OTEL_TRACES_EXPORTER", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
		metricEnabled, metricErr = signalEnabled(os.LookupEnv, "OTEL_METRICS_EXPORTER", "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT")
		problems = compactErrors(traceErr, metricErr)
	}
	if !traceEnabled && !metricEnabled {
		return provider, problems
	}

	otel.SetErrorHandler(otel.ErrorHandlerFunc(options.OnError))
	identity := resource.NewSchemaless(
		semconv.ServiceName("ci-runner-controller"),
		semconv.ServiceNamespace("melodic-software"),
		semconv.ServiceVersion(options.Version),
		semconv.ServiceInstanceID(options.HostID),
		semconv.HostName(options.HostID),
	)

	var tracerProvider apiTrace.TracerProvider = tracenoop.NewTracerProvider()
	if traceEnabled {
		protocol, protocolErr := traceProtocol, error(nil)
		if options.Export == nil {
			protocol, protocolErr = signalProtocol(os.LookupEnv, "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL")
		}
		if protocolErr != nil {
			problems = append(problems, protocolErr)
		} else if exporter, exporterErr := newTraceExporter(ctx, protocol, endpoint); exporterErr != nil {
			problems = append(problems, fmt.Errorf("initialize OTLP trace exporter: %w", exporterErr))
		} else {
			traces := sdktrace.NewTracerProvider(sdktrace.WithResource(identity), sdktrace.WithBatcher(exporter))
			tracerProvider = traces
			provider.shutdown = append(provider.shutdown, traces.Shutdown)
			provider.enabled = true
		}
	}

	var meterProvider apiMetric.MeterProvider = metricnoop.NewMeterProvider()
	if metricEnabled {
		protocol, protocolErr := metricProtocol, error(nil)
		interval, timeout := metricInterval, metricTimeout
		var intervalErr, timeoutErr error
		if options.Export == nil {
			protocol, protocolErr = signalProtocol(os.LookupEnv, "OTEL_EXPORTER_OTLP_METRICS_PROTOCOL")
			interval, intervalErr = millisecondsEnvironment(os.LookupEnv, "OTEL_METRIC_EXPORT_INTERVAL", defaultMetricExportInterval)
			timeout, timeoutErr = millisecondsEnvironment(os.LookupEnv, "OTEL_METRIC_EXPORT_TIMEOUT", defaultMetricExportTimeout)
		}
		if err := errors.Join(protocolErr, intervalErr, timeoutErr); err != nil {
			problems = append(problems, err)
		} else if exporter, exporterErr := newMetricExporter(ctx, protocol, endpoint); exporterErr != nil {
			problems = append(problems, fmt.Errorf("initialize OTLP metric exporter: %w", exporterErr))
		} else {
			reader := metric.NewPeriodicReader(exporter, metric.WithInterval(interval), metric.WithTimeout(timeout))
			metrics := metric.NewMeterProvider(metric.WithResource(identity), metric.WithReader(reader))
			meterProvider = metrics
			provider.shutdown = append(provider.shutdown, metrics.Shutdown)
			provider.enabled = true
		}
	}

	recorder, instrumentErr := newRecorder(tracerProvider, meterProvider)
	if instrumentErr != nil {
		problems = append(problems, fmt.Errorf("create telemetry instruments: %w", instrumentErr))
		return provider, problems
	}
	provider.recorder = recorder
	return provider, problems
}

func newTraceExporter(ctx context.Context, protocol, endpoint string) (sdktrace.SpanExporter, error) {
	if protocol == "grpc" {
		if endpoint != "" {
			return otlptracegrpc.New(ctx, otlptracegrpc.WithEndpointURL(endpoint))
		}
		return otlptracegrpc.New(ctx)
	}
	if endpoint != "" {
		return otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(httpSignalEndpoint(endpoint, "traces")))
	}
	return otlptracehttp.New(ctx)
}

func newMetricExporter(ctx context.Context, protocol, endpoint string) (metric.Exporter, error) {
	if protocol == "grpc" {
		if endpoint != "" {
			return otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithEndpointURL(endpoint))
		}
		return otlpmetricgrpc.New(ctx)
	}
	if endpoint != "" {
		return otlpmetrichttp.New(ctx, otlpmetrichttp.WithEndpointURL(httpSignalEndpoint(endpoint, "metrics")))
	}
	return otlpmetrichttp.New(ctx)
}

func httpSignalEndpoint(base, signal string) string {
	return strings.TrimRight(base, "/") + "/v1/" + signal
}

type environmentLookup func(string) (string, bool)

func sdkDisabled(lookup environmentLookup) (bool, error) {
	raw, present := lookup("OTEL_SDK_DISABLED")
	if !present || strings.TrimSpace(raw) == "" {
		return false, nil
	}
	value, err := strconv.ParseBool(strings.TrimSpace(raw))
	if err != nil {
		return true, fmt.Errorf("OTEL_SDK_DISABLED must be a boolean: %w", err)
	}
	return value, nil
}

func signalEnabled(lookup environmentLookup, exporterVariable, signalEndpointVariable string) (bool, error) {
	if raw, present := lookup(exporterVariable); present && strings.TrimSpace(raw) != "" {
		switch strings.ToLower(strings.TrimSpace(raw)) {
		case "none":
			return false, nil
		case "otlp":
			return true, nil
		default:
			return false, fmt.Errorf("%s supports only otlp or none", exporterVariable)
		}
	}
	for _, variable := range []string{signalEndpointVariable, "OTEL_EXPORTER_OTLP_ENDPOINT"} {
		if raw, present := lookup(variable); present && strings.TrimSpace(raw) != "" {
			return true, nil
		}
	}
	return false, nil
}

func signalProtocol(lookup environmentLookup, signalVariable string) (string, error) {
	raw, present := lookup(signalVariable)
	if !present || strings.TrimSpace(raw) == "" {
		raw, present = lookup("OTEL_EXPORTER_OTLP_PROTOCOL")
	}
	if !present || strings.TrimSpace(raw) == "" {
		return "http/protobuf", nil
	}
	protocol := strings.ToLower(strings.TrimSpace(raw))
	if protocol != "http/protobuf" && protocol != "grpc" {
		return "", fmt.Errorf("%s must be http/protobuf or grpc", signalVariable)
	}
	return protocol, nil
}

func millisecondsEnvironment(lookup environmentLookup, variable string, fallback time.Duration) (time.Duration, error) {
	raw, present := lookup(variable)
	if !present || strings.TrimSpace(raw) == "" {
		return fallback, nil
	}
	value, err := strconv.ParseInt(strings.TrimSpace(raw), 10, 64)
	if err != nil || value <= 0 || value > mathMaxMilliseconds() {
		return 0, fmt.Errorf("%s must be a positive millisecond integer", variable)
	}
	return time.Duration(value) * time.Millisecond, nil
}

func mathMaxMilliseconds() int64 { return int64(^uint64(0)>>1) / int64(time.Millisecond) }

func compactErrors(values ...error) []error {
	result := make([]error, 0, len(values))
	for _, value := range values {
		if value != nil {
			result = append(result, value)
		}
	}
	return result
}
