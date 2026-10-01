//go:build windows

package host

import (
	"context"
	"errors"
	"os/exec"
	"reflect"
	"testing"
)

type recordingCommandRunner struct {
	name string
	args []string
	out  []byte
	err  error
}

func (r *recordingCommandRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	r.name = name
	r.args = append([]string(nil), args...)
	return r.out, r.err
}

func TestDockerDesktopStatusClassifiesNonZeroExit(t *testing.T) {
	t.Parallel()
	// A stopped Docker Desktop makes `docker desktop status` exit non-zero, so the
	// runner returns a genuine *exec.ExitError. Produce one rather than a sentinel
	// so errors.As exercises the same classification path the CLI hits in the wild.
	exitErr := exec.CommandContext(context.Background(), "cmd", "/c", "exit 1").Run()
	var asExit *exec.ExitError
	if !errors.As(exitErr, &asExit) {
		t.Fatalf("prerequisite: %v is not an *exec.ExitError", exitErr)
	}
	executable := `C:\Program Files\Docker\Docker\resources\bin\docker.exe`
	tests := []struct {
		name    string
		out     []byte
		err     error
		want    DesktopStatus
		wantErr bool
	}{
		{name: "stopped output on non-zero exit", out: []byte("stopped"), err: exitErr, want: DesktopStatusStopped},
		{name: "empty output on non-zero exit", out: nil, err: exitErr, want: DesktopStatusStopped},
		{name: "running output on non-zero exit", out: []byte(`{"Status":"running"}`), err: exitErr, want: DesktopStatusRunning},
		{name: "non-exit error propagates", out: nil, err: errors.New("docker.exe not found"), wantErr: true},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			runner := &recordingCommandRunner{out: test.out, err: test.err}
			status, err := DockerDesktopCLI{Runner: runner, executablePath: executable}.Status(context.Background())
			if test.wantErr {
				if err == nil {
					t.Fatalf("expected error, got status %v", status)
				}
				if status != DesktopStatusUnknown {
					t.Fatalf("status = %v, want DesktopStatusUnknown on a non-exit error", status)
				}
				return
			}
			if err != nil {
				t.Fatalf("Status: %v", err)
			}
			if status != test.want {
				t.Fatalf("status = %v, want %v", status, test.want)
			}
		})
	}
}

func TestDockerDesktopStatusPreservesContextCancellation(t *testing.T) {
	t.Parallel()
	// A canceled or expired context kills the probe process, which also surfaces
	// as an *exec.ExitError. That aborted probe must propagate the context error
	// instead of classifying the desktop as stopped: in watchdog and shutdown
	// paths a timed-out probe otherwise records a known-stopped desktop and
	// skips the Docker worker inventory.
	exitErr := exec.CommandContext(context.Background(), "cmd", "/c", "exit 1").Run()
	var asExit *exec.ExitError
	if !errors.As(exitErr, &asExit) {
		t.Fatalf("prerequisite: %v is not an *exec.ExitError", exitErr)
	}
	executable := `C:\Program Files\Docker\Docker\resources\bin\docker.exe`
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	runner := &recordingCommandRunner{out: nil, err: exitErr}
	status, err := DockerDesktopCLI{Runner: runner, executablePath: executable}.Status(ctx)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want the context cancellation preserved", err)
	}
	if status != DesktopStatusUnknown {
		t.Fatalf("status = %v, want DesktopStatusUnknown for an aborted probe", status)
	}
}

func TestDockerInspectorPinsLocalEngineHost(t *testing.T) {
	t.Parallel()
	executable := `C:\Program Files\Docker\Docker\resources\bin\docker.exe`
	tests := []struct {
		name string
		run  func(DockerCLIInspector) error
		want []string
	}{
		{
			name: "info",
			run: func(inspector DockerCLIInspector) error {
				_, err := inspector.EngineReachable(context.Background())
				return err
			},
			want: []string{"--host", localDockerEngineHost, "info", "--format", "{{json .ServerVersion}}"},
		},
		{
			name: "containers",
			run: func(inspector DockerCLIInspector) error {
				_, err := inspector.Containers(context.Background())
				return err
			},
			want: []string{"--host", localDockerEngineHost, "ps", "--format", "{{json .}}"},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			runner := &recordingCommandRunner{}
			if err := test.run(DockerCLIInspector{Runner: runner, executablePath: executable}); err != nil {
				t.Fatal(err)
			}
			if runner.name != executable || !reflect.DeepEqual(runner.args, test.want) {
				t.Fatalf("command = %q %#v, want %q %#v", runner.name, runner.args, executable, test.want)
			}
		})
	}
}
