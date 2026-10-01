package controller

import (
	"context"
	"errors"
	"fmt"
	"sort"

	"github.com/melodic-software/ci-runner/internal/model"
)

var ErrForceStopStateChanged = errors.New("managed worker state changed after force-stop preview")

// ForceStopRuntime is intentionally separate from WorkerRuntime. The normal
// reconciliation state machine cannot terminate busy work; only the explicit,
// confirmed command path receives this capability.
type ForceStopRuntime interface {
	WorkerRuntime
	ForceStop(context.Context, string) error
}

type ForceStopTarget struct {
	WorkerID string            `json:"workerId"`
	PoolID   string            `json:"poolId"`
	Name     string            `json:"name"`
	State    model.WorkerState `json:"state"`
	JobID    string            `json:"jobId,omitempty"`
}

// ForceStopPreview returns the exact set that must be shown before typed
// confirmation. Callers must first request disabled mode and observe every
// listener advertising zero capacity.
func ForceStopPreview(ctx context.Context, runtime WorkerRuntime) ([]ForceStopTarget, error) {
	workers, err := runtime.List(ctx)
	if err != nil {
		return nil, err
	}
	return forceStopTargets(workers), nil
}

// ExecuteForceStop re-inventories and requires an exact match with the preview;
// a newly acquired job or any other lifecycle change invalidates confirmation.
func ExecuteForceStop(ctx context.Context, runtime ForceStopRuntime, expected []ForceStopTarget) ([]ForceStopTarget, error) {
	workers, err := runtime.List(ctx)
	if err != nil {
		return nil, err
	}
	actual := forceStopTargets(workers)
	if !sameForceStopTargets(expected, actual) {
		return actual, ErrForceStopStateChanged
	}
	var stopErrors []error
	for _, target := range actual {
		if err := ctx.Err(); err != nil {
			stopErrors = append(stopErrors, err)
			break
		}
		if err := runtime.ForceStop(ctx, target.WorkerID); err != nil {
			stopErrors = append(stopErrors, fmt.Errorf("force stop worker %s: %w", target.WorkerID, err))
		}
	}
	return actual, errors.Join(stopErrors...)
}

func forceStopTargets(workers []model.Worker) []ForceStopTarget {
	targets := make([]ForceStopTarget, 0, len(workers))
	for _, worker := range workers {
		if !worker.Active() {
			continue
		}
		targets = append(targets, ForceStopTarget{
			WorkerID: worker.ID, PoolID: worker.PoolID, Name: worker.Name, State: worker.State, JobID: worker.JobID,
		})
	}
	sort.Slice(targets, func(i, j int) bool { return targets[i].WorkerID < targets[j].WorkerID })
	return targets
}

func sameForceStopTargets(a, b []ForceStopTarget) bool {
	if len(a) != len(b) {
		return false
	}
	a = append([]ForceStopTarget(nil), a...)
	b = append([]ForceStopTarget(nil), b...)
	sort.Slice(a, func(i, j int) bool { return a[i].WorkerID < a[j].WorkerID })
	sort.Slice(b, func(i, j int) bool { return b[i].WorkerID < b[j].WorkerID })
	for index := range a {
		if a[index] != b[index] {
			return false
		}
	}
	return true
}
