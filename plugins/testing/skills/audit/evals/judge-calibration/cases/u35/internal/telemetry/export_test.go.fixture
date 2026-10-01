package telemetry

import (
	"context"
	"strings"
	"testing"
)

func TestTelemetryIsDisabledWhenStandardOTELConfigurationIsUnset(t *testing.T) {
	for _, variable := range telemetryEnvironmentVariables() {
		t.Setenv(variable, "")
	}
	provider, problems := NewFromEnv(context.Background(), Options{HostID: "melo-desk-001", Version: "1.2.3"})
	if len(problems) != 0 {
		t.Fatalf("problems = %v", problems)
	}
	if provider.enabled || len(provider.shutdown) != 0 {
		t.Fatalf("unset telemetry created exporter state: %#v", provider)
	}
	if err := provider.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestConfiguredExportUsesReviewedSettingsInsteadOfSignalEnvironment(t *testing.T) {
	for _, variable := range telemetryEnvironmentVariables() {
		t.Setenv(variable, "")
	}
	t.Setenv("OTEL_SDK_DISABLED", "true")
	t.Setenv("OTEL_TRACES_EXPORTER", "none")
	provider, problems := NewFromEnv(context.Background(), Options{
		HostID: "melo-desk-001", Version: "1.2.3",
		Export: &ExportConfig{
			Endpoint: "http://127.0.0.1:4317", Protocol: "grpc",
			Traces: true,
		},
	})
	if len(problems) != 0 || !provider.enabled || len(provider.shutdown) != 1 {
		t.Fatalf("configured provider = %#v, problems = %v", provider, problems)
	}
	if err := provider.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestHTTPSignalEndpointUsesStandardSignalPaths(t *testing.T) {
	t.Parallel()
	if got := httpSignalEndpoint("http://collector:4318/base/", "traces"); got != "http://collector:4318/base/v1/traces" {
		t.Fatalf("trace endpoint = %q", got)
	}
	if got := httpSignalEndpoint("http://collector:4318", "metrics"); got != "http://collector:4318/v1/metrics" {
		t.Fatalf("metric endpoint = %q", got)
	}
}

func TestOTELSDKDisabledOverridesConfiguredEndpoint(t *testing.T) {
	for _, variable := range telemetryEnvironmentVariables() {
		t.Setenv(variable, "")
	}
	t.Setenv("OTEL_SDK_DISABLED", "true")
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:4318")
	provider, problems := NewFromEnv(context.Background(), Options{HostID: "melo-desk-001", Version: "1.2.3"})
	if len(problems) != 0 || provider.enabled {
		t.Fatalf("disabled provider = %#v, problems = %v", provider, problems)
	}
}

func TestInvalidSDKDisabledFailsSafelyWithoutExporter(t *testing.T) {
	for _, variable := range telemetryEnvironmentVariables() {
		t.Setenv(variable, "")
	}
	t.Setenv("OTEL_SDK_DISABLED", "sometimes")
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:4318")
	provider, problems := NewFromEnv(context.Background(), Options{HostID: "melo-desk-001", Version: "1.2.3"})
	if provider.enabled || len(problems) != 1 || !strings.Contains(problems[0].Error(), "OTEL_SDK_DISABLED") {
		t.Fatalf("provider = %#v, problems = %v", provider, problems)
	}
}

func TestSignalEnablementAndProtocolPrecedence(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		values   map[string]string
		enabled  bool
		protocol string
		wantErr  bool
	}{
		{name: "unset", values: map[string]string{}, protocol: "http/protobuf"},
		{name: "generic endpoint", values: map[string]string{"OTEL_EXPORTER_OTLP_ENDPOINT": "http://collector:4318"}, enabled: true, protocol: "http/protobuf"},
		{name: "explicit none wins", values: map[string]string{"OTEL_EXPORTER_OTLP_ENDPOINT": "http://collector:4318", "OTEL_TRACES_EXPORTER": "none"}, protocol: "http/protobuf"},
		{name: "explicit otlp defaults locally", values: map[string]string{"OTEL_TRACES_EXPORTER": "otlp"}, enabled: true, protocol: "http/protobuf"},
		{name: "signal protocol wins", values: map[string]string{"OTEL_TRACES_EXPORTER": "otlp", "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf", "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL": "grpc"}, enabled: true, protocol: "grpc"},
		{name: "unsupported exporter", values: map[string]string{"OTEL_TRACES_EXPORTER": "console"}, protocol: "http/protobuf", wantErr: true},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			lookup := mapLookup(test.values)
			enabled, enableErr := signalEnabled(lookup, "OTEL_TRACES_EXPORTER", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
			protocol, protocolErr := signalProtocol(lookup, "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL")
			if (enableErr != nil || protocolErr != nil) != test.wantErr {
				t.Fatalf("enable error = %v, protocol error = %v", enableErr, protocolErr)
			}
			if enabled != test.enabled || protocol != test.protocol {
				t.Fatalf("enabled/protocol = %t/%q, want %t/%q", enabled, protocol, test.enabled, test.protocol)
			}
		})
	}
}

func mapLookup(values map[string]string) environmentLookup {
	return func(key string) (string, bool) {
		value, found := values[key]
		return value, found
	}
}

func telemetryEnvironmentVariables() []string {
	return []string{
		"OTEL_SDK_DISABLED", "OTEL_TRACES_EXPORTER", "OTEL_METRICS_EXPORTER",
		"OTEL_EXPORTER_OTLP_ENDPOINT", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
		"OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", "OTEL_EXPORTER_OTLP_PROTOCOL",
		"OTEL_EXPORTER_OTLP_TRACES_PROTOCOL", "OTEL_EXPORTER_OTLP_METRICS_PROTOCOL",
		"OTEL_METRIC_EXPORT_INTERVAL", "OTEL_METRIC_EXPORT_TIMEOUT",
	}
}
