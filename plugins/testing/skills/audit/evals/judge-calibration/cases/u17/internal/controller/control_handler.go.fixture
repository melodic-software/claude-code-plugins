package controller

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/melodic-software/ci-runner/internal/control"
	"github.com/melodic-software/ci-runner/internal/model"
	statepkg "github.com/melodic-software/ci-runner/internal/state"
)

type ShutdownSignal struct {
	RequestID string
	Reason    string
	Restart   bool
}

// ControlHandler bridges the authenticated local transport to the reconciler.
// Shutdown is two-phase: Handle reserves the transition; CommitShutdown starts
// it only after the server has flushed the acceptance response.
type ControlHandler struct {
	reconciler *Reconciler
	processID  uint32

	mu               sync.Mutex
	pendingRequestID string
	pendingReason    string
	pendingRestart   bool
	committed        bool
	shutdown         chan ShutdownSignal
}

func NewControlHandler(reconciler *Reconciler, processID uint32) (*ControlHandler, error) {
	if reconciler == nil || processID == 0 {
		return nil, errors.New("controller reconciler and process ID are required")
	}
	return &ControlHandler{reconciler: reconciler, processID: processID, shutdown: make(chan ShutdownSignal, 1)}, nil
}

func (h *ControlHandler) ShutdownRequests() <-chan ShutdownSignal { return h.shutdown }

func (h *ControlHandler) Handle(ctx context.Context, request control.Request) control.Response {
	if err := request.Validate(); err != nil {
		return control.ErrorResponse(request.RequestID, "invalid-request", err)
	}
	status, err := h.status(ctx)
	if err != nil {
		return control.ErrorResponse(request.RequestID, "status-unavailable", err)
	}
	response := control.Response{SchemaVersion: control.SchemaVersion, RequestID: request.RequestID, OK: true, Status: &status}
	switch request.Operation {
	case control.OperationStatus:
		return response
	case control.OperationForceStopPreview:
		if err := h.forceStopAllowed(ctx); err != nil {
			return control.ErrorResponse(request.RequestID, "force-stop-not-drained", err)
		}
		targets, err := ForceStopPreview(ctx, h.reconciler.deps.Workers)
		if err != nil {
			return control.ErrorResponse(request.RequestID, "force-stop-preview-error", err)
		}
		response.ForceStopTargets = toControlForceStopTargets(targets)
		return response
	case control.OperationForceStopExecute:
		if err := h.forceStopAllowed(ctx); err != nil {
			return control.ErrorResponse(request.RequestID, "force-stop-not-drained", err)
		}
		runtime, ok := h.reconciler.deps.Workers.(ForceStopRuntime)
		if !ok {
			return control.ErrorResponse(request.RequestID, "force-stop-unavailable", errors.New("controller worker runtime does not expose explicit force-stop"))
		}
		actual, err := ExecuteForceStop(ctx, runtime, fromControlForceStopTargets(request.ForceStop.Expected))
		if errors.Is(err, ErrForceStopStateChanged) {
			result := control.ErrorResponse(request.RequestID, "force-stop-state-changed", err)
			result.ForceStopTargets = toControlForceStopTargets(actual)
			return result
		}
		if err != nil {
			return control.ErrorResponse(request.RequestID, "force-stop-error", err)
		}
		response.ForceStopTargets = toControlForceStopTargets(actual)
		return response
	case control.OperationShutdown:
		// Continue through the two-phase shutdown reservation below.
	}
	if status.AssignedJobCount != request.Shutdown.ExpectedAssignedJobCount ||
		status.ActiveJobCount != request.Shutdown.ExpectedActiveJobCount ||
		status.ActiveWorkerCount != request.Shutdown.ExpectedActiveWorkerCount {
		return control.ErrorResponse(request.RequestID, "shutdown-state-changed", errors.New("assigned jobs or active workers changed after shutdown preflight; shutdown was not accepted"))
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	if h.pendingRequestID != "" && h.pendingRequestID != request.RequestID {
		return control.ErrorResponse(request.RequestID, "shutdown-in-progress", errors.New("a graceful shutdown is already in progress"))
	}
	if h.pendingRequestID == "" {
		h.pendingRequestID = request.RequestID
		h.pendingReason = request.Shutdown.Reason
		h.pendingRestart = request.Shutdown.RestartViaTaskScheduler
	}
	response.Status.ShuttingDown = true
	return response
}

func (h *ControlHandler) forceStopAllowed(ctx context.Context) error {
	desired, err := h.reconciler.deps.State.LoadDesired(ctx)
	if err != nil {
		return fmt.Errorf("load desired state: %w", err)
	}
	if desired.Mode != model.ModeDisabled {
		return errors.New("force-stop requires desired mode disabled")
	}
	observed, err := h.reconciler.deps.State.LoadObserved(ctx)
	if err != nil {
		return fmt.Errorf("load observed state: %w", err)
	}
	if observed.Phase != model.PhaseDraining && observed.Phase != model.PhaseDisabled {
		return fmt.Errorf("force-stop requires draining or disabled phase, not %s", observed.Phase)
	}
	seen := make(map[string]bool, len(observed.Pools))
	for _, pool := range observed.Pools {
		seen[pool.ID] = true
		if !pool.CapacityAcknowledged {
			return fmt.Errorf("pool %s has no current capacity acknowledgement", pool.ID)
		}
		if pool.MaxCapacity != 0 {
			return fmt.Errorf("pool %s still advertises capacity %d", pool.ID, pool.MaxCapacity)
		}
	}
	for _, target := range h.reconciler.config.GitHub.Targets {
		if !seen[target.ID] {
			return fmt.Errorf("pool %s has no observed zero-capacity acknowledgement", target.ID)
		}
	}
	return nil
}

func toControlForceStopTargets(targets []ForceStopTarget) []control.ForceStopTarget {
	result := make([]control.ForceStopTarget, 0, len(targets))
	for _, target := range targets {
		result = append(result, control.ForceStopTarget{
			WorkerID: target.WorkerID, PoolID: target.PoolID, Name: target.Name, State: target.State, JobID: target.JobID,
		})
	}
	return result
}

func fromControlForceStopTargets(targets []control.ForceStopTarget) []ForceStopTarget {
	result := make([]ForceStopTarget, 0, len(targets))
	for _, target := range targets {
		result = append(result, ForceStopTarget{
			WorkerID: target.WorkerID, PoolID: target.PoolID, Name: target.Name, State: target.State, JobID: target.JobID,
		})
	}
	return result
}

func (h *ControlHandler) CommitShutdown(requestID string) {
	h.mu.Lock()
	if requestID == "" || requestID != h.pendingRequestID || h.committed {
		h.mu.Unlock()
		return
	}
	h.committed = true
	signal := ShutdownSignal{RequestID: requestID, Reason: h.pendingReason, Restart: h.pendingRestart}
	h.mu.Unlock()

	h.reconciler.BeginShutdown()
	h.shutdown <- signal
}

// AbortShutdown releases only an uncommitted reservation for the exact
// request whose acceptance response could not be flushed. A committed drain is
// irreversible through this path.
func (h *ControlHandler) AbortShutdown(requestID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if requestID == "" || requestID != h.pendingRequestID || h.committed {
		return
	}
	h.pendingRequestID = ""
	h.pendingReason = ""
	h.pendingRestart = false
}

func (h *ControlHandler) status(ctx context.Context) (control.Status, error) {
	observed, err := h.reconciler.deps.State.LoadObserved(ctx)
	if errors.Is(err, statepkg.ErrNotFound) {
		observed = model.ObservedState{SchemaVersion: 1, Phase: model.PhaseStarting}
	} else if err != nil {
		return control.Status{}, err
	}
	assignedJobs := 0
	activeJobs := 0
	activeWorkers := 0
	maximumInt := int(^uint(0) >> 1)
	for _, pool := range observed.Pools {
		if pool.TotalAssignedJobs < 0 || assignedJobs > maximumInt-pool.TotalAssignedJobs {
			return control.Status{}, errors.New("observed assigned-job count is invalid")
		}
		assignedJobs += pool.TotalAssignedJobs
	}
	for _, worker := range observed.Workers {
		if worker.Active() {
			activeWorkers++
		}
		if worker.State == model.WorkerBusy {
			activeJobs++
		}
	}
	h.mu.Lock()
	pending := h.pendingRequestID != ""
	h.mu.Unlock()
	return control.Status{
		Phase: observed.Phase, ProcessID: h.processID, Version: h.reconciler.version,
		AssignedJobCount: assignedJobs, ActiveJobCount: activeJobs, ActiveWorkerCount: activeWorkers,
		ShuttingDown: pending || h.reconciler.ShuttingDown(),
	}, nil
}

var _ control.Handler = (*ControlHandler)(nil)
