package controller

import (
	"context"
	"errors"
	"time"

	clockpkg "github.com/melodic-software/ci-runner/internal/clock"
	"github.com/melodic-software/ci-runner/internal/config"
	"github.com/melodic-software/ci-runner/internal/model"
	"github.com/melodic-software/ci-runner/internal/scaleset"
	statepkg "github.com/melodic-software/ci-runner/internal/state"
)

type ScaleSetClient interface{ scaleset.Client }
type StateStore interface{ statepkg.Store }
type Clock interface{ clockpkg.Clock }

type JobLookup interface {
	ActiveJob(context.Context, string, string) (string, bool, error)
}

type StartWorkerRequest struct {
	PoolID    string
	Name      string
	JITConfig scaleset.JITConfig
	Limits    config.Worker
}

type WorkerStartError struct {
	Err               error
	RunnerMayBeActive bool
}

func (e *WorkerStartError) Error() string { return e.Err.Error() }
func (e *WorkerStartError) Unwrap() error { return e.Err }

// RunnerStartMayBeActive fails closed for untyped runtime errors.
func RunnerStartMayBeActive(err error) bool {
	var typed *WorkerStartError
	return !errors.As(err, &typed) || typed.RunnerMayBeActive
}

type WorkerRuntime interface {
	List(context.Context) ([]model.Worker, error)
	Start(context.Context, StartWorkerRequest) (model.Worker, error)
	// RemoveIfIdle must re-check the worker at the point of removal and return
	// false without stopping it if work has been acquired. This is the final
	// defense against a job-acquisition race during drain.
	RemoveIfIdle(context.Context, string) (bool, error)
}

type DesktopManager interface {
	Status(context.Context) (model.DesktopStatus, error)
	Start(context.Context, time.Duration) error
	Stop(context.Context, time.Duration) error
	ShutdownAllWSL(context.Context) error
}

type PowerMonitor interface {
	Snapshot(context.Context) (model.PowerSnapshot, error)
}

type ResourceMonitor interface {
	Snapshot(context.Context) (model.ResourceSnapshot, error)
}

type SecretMaterial = scaleset.SecretMaterial
type SecretStore = scaleset.SecretStore

var NewSecretMaterial = scaleset.NewSecretMaterial

type LogEvent struct {
	At       time.Time
	Code     string
	Message  string
	PoolID   string
	WorkerID string
}

type LogSink interface {
	Write(context.Context, LogEvent) error
}

type DiscardLogSink struct{}

func (DiscardLogSink) Write(context.Context, LogEvent) error { return nil }
