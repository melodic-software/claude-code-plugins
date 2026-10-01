// Package telemetry provides the controller's low-cardinality OpenTelemetry
// contract. Callers pass only aggregate fleet state; runner names, job IDs,
// container IDs, credentials, and GitHub request payloads never cross it.
package telemetry

import (
	"context"
	"errors"
	"math"
	"slices"
	"strings"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
)

const instrumentationName = "github.com/melodic-software/ci-runner/internal/telemetry"

var workerStates = [...]string{"starting", "idle", "busy", "unregistered", "exited"}

// Recorder is deliberately infallible. Telemetry must never participate in
// worker admission, draining, finalization, or controller shutdown decisions.
type Recorder interface {
	BeginReconcile(context.Context) (context.Context, func(ReconcileSnapshot, error))
	WorkerRegistered(context.Context, string, string, time.Duration, WorkerStartOutcome)
	WorkerStarted(context.Context, string, string, time.Duration, WorkerStartOutcome)
	WorkerFinalized(context.Context, string, WorkerFinalization)
	ObserveJobStarted(context.Context, string, time.Duration)
	ObserveJobCompleted(context.Context, string, string, bool)
}

type ReconcilePool struct {
	ID                             string
	Advertised                     int
	Assigned                       int
	Desired                        int
	AffordableWorkers              int
	CapacityAcknowledged           bool
	AcknowledgementPendingAge      time.Duration
	AcknowledgementPendingAgeValid bool
}

type ReconcileWorker struct {
	PoolID string
	State  string
}

type ReconcileSnapshot struct {
	Valid                bool
	Phase                string
	Pools                []ReconcilePool
	Workers              []ReconcileWorker
	CPUPercent           float64
	AvailableMemoryBytes uint64
	MemoryHeadroomBytes  uint64
	ResourceGateBlocked  bool
	PowerGateBlocked     bool
	CheckpointAge        time.Duration
	CheckpointAgeValid   bool
}

type WorkerStartOutcome string

const (
	WorkerStartSucceeded WorkerStartOutcome = "succeeded"
	WorkerStartFailed    WorkerStartOutcome = "failed"
	WorkerStartAmbiguous WorkerStartOutcome = "ambiguous"
	WorkerStartCanceled  WorkerStartOutcome = "canceled"
)

func ClassifyWorkerStart(err error, mayBeActive bool) WorkerStartOutcome {
	if err == nil {
		return WorkerStartSucceeded
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return WorkerStartCanceled
	}
	if mayBeActive {
		return WorkerStartAmbiguous
	}
	return WorkerStartFailed
}

type WorkerFinalization struct {
	ExitCode               int64
	ExitObserved           bool
	Err                    error
	ControllerShutdown     bool
	ResourceTier           string
	ResourceEvidence       *WorkerResourceEvidence
	RecordResourceEvidence bool
	Duration               time.Duration
}

type WorkerResourceEvidence struct {
	Status                   string
	Missing                  []string
	MemoryPeakBytes          uint64
	MemorySwapPeakBytes      uint64
	OOMEvents                uint64
	OOMKillEvents            uint64
	CPUPeriods               uint64
	CPUThrottledPeriods      uint64
	CPUThrottledMicroseconds uint64
	PIDsPeak                 uint64
	IOReadBytes              uint64
	IOWriteBytes             uint64
}

type WorkerFinalizationOutcome string

const (
	WorkerFinalizationCompleted    WorkerFinalizationOutcome = "completed"
	WorkerFinalizationWorkerError  WorkerFinalizationOutcome = "worker_error"
	WorkerFinalizationRuntimeError WorkerFinalizationOutcome = "runtime_error"
	WorkerFinalizationCanceled     WorkerFinalizationOutcome = "canceled"
	WorkerFinalizationUnknown      WorkerFinalizationOutcome = "unknown"
)

// ClassifyWorkerFinalization uses the container lifecycle, not log text. The
// one-shot GitHub runner can log TaskCanceledException while shutting down its
// broker poll after a successful job; a zero container exit remains completed.
func ClassifyWorkerFinalization(value WorkerFinalization) WorkerFinalizationOutcome {
	if value.ControllerShutdown {
		return WorkerFinalizationCanceled
	}
	if value.Err != nil {
		return WorkerFinalizationRuntimeError
	}
	if !value.ExitObserved {
		return WorkerFinalizationUnknown
	}
	if value.ExitCode == 0 {
		return WorkerFinalizationCompleted
	}
	return WorkerFinalizationWorkerError
}

type noopRecorder struct{}

func Noop() Recorder { return noopRecorder{} }

func (noopRecorder) BeginReconcile(ctx context.Context) (context.Context, func(ReconcileSnapshot, error)) {
	return ctx, func(ReconcileSnapshot, error) {}
}
func (noopRecorder) WorkerRegistered(context.Context, string, string, time.Duration, WorkerStartOutcome) {
}
func (noopRecorder) WorkerStarted(context.Context, string, string, time.Duration, WorkerStartOutcome) {
}
func (noopRecorder) WorkerFinalized(context.Context, string, WorkerFinalization) {}
func (noopRecorder) ObserveJobStarted(context.Context, string, time.Duration)    {}
func (noopRecorder) ObserveJobCompleted(context.Context, string, string, bool)   {}

type recorder struct {
	tracer trace.Tracer

	reconcileDuration         metric.Float64Histogram
	reconcileErrors           metric.Int64Counter
	checkpointAge             metric.Float64Gauge
	advertised                metric.Int64Gauge
	capacityAcknowledged      metric.Int64Gauge
	acknowledgementPendingAge metric.Float64Gauge
	assigned                  metric.Int64Gauge
	desired                   metric.Int64Gauge
	workers                   metric.Int64Gauge
	activeJobs                metric.Int64Gauge
	inventoryWorkers          metric.Int64Gauge
	assignmentGap             metric.Int64Gauge
	transientLag              metric.Int64Gauge
	cpuPercent                metric.Float64Gauge
	availableMemory           metric.Int64Gauge
	memoryHeadroom            metric.Int64Gauge
	memoryAffordable          metric.Int64Gauge
	resourceGate              metric.Int64Gauge
	powerGate                 metric.Int64Gauge
	workerStarts              metric.Int64Counter
	workerStartTime           metric.Float64Histogram
	workerRegisters           metric.Int64Counter
	workerRegisterTime        metric.Float64Histogram
	workerFinalizes           metric.Int64Counter
	workerFinalizeTime        metric.Float64Histogram
	jobsStarted               metric.Int64Counter
	jobStartLag               metric.Float64Histogram
	lifecycleEventTime        metric.Float64Gauge
	jobsCompleted             metric.Int64Counter
	cancellations             metric.Int64Counter
	resourceEvidence          metric.Int64Counter
	memoryPeak                metric.Int64Histogram
	memorySwapPeak            metric.Int64Histogram
	oomEvents                 metric.Int64Counter
	oomKillEvents             metric.Int64Counter
	cpuPeriods                metric.Int64Histogram
	cpuThrottled              metric.Int64Histogram
	cpuThrottledTime          metric.Float64Histogram
	pidsPeak                  metric.Int64Histogram
	ioRead                    metric.Int64Histogram
	ioWrite                   metric.Int64Histogram
}

func newRecorder(tracerProvider trace.TracerProvider, meterProvider metric.MeterProvider) (*recorder, error) {
	meter := meterProvider.Meter(instrumentationName)
	r := &recorder{tracer: tracerProvider.Tracer(instrumentationName)}
	var err error
	if r.reconcileDuration, err = meter.Float64Histogram("ci_runner.controller.reconcile.duration", metric.WithUnit("s"), metric.WithDescription("Controller reconciliation duration.")); err != nil {
		return nil, err
	}
	if r.reconcileErrors, err = meter.Int64Counter("ci_runner.controller.reconcile.errors", metric.WithUnit("{error}"), metric.WithDescription("Unexpected reconciliation errors.")); err != nil {
		return nil, err
	}
	if r.checkpointAge, err = meter.Float64Gauge("ci_runner.controller.observed.checkpoint.age", metric.WithUnit("s"), metric.WithDescription("Age of the prior durable observed checkpoint when reconciliation began.")); err != nil {
		return nil, err
	}
	if r.advertised, err = meter.Int64Gauge("ci_runner.capacity.advertised", metric.WithUnit("{worker}"), metric.WithDescription("Capacity acknowledged to GitHub by target pool.")); err != nil {
		return nil, err
	}
	if r.capacityAcknowledged, err = meter.Int64Gauge("ci_runner.capacity.acknowledged", metric.WithUnit("1"), metric.WithDescription("Whether the latest target capacity is acknowledged by the GitHub listener.")); err != nil {
		return nil, err
	}
	if r.acknowledgementPendingAge, err = meter.Float64Gauge("ci_runner.capacity.acknowledgement.pending.age", metric.WithUnit("s"), metric.WithDescription("Age of the current unacknowledged capacity transition; omitted when acknowledged or unavailable.")); err != nil {
		return nil, err
	}
	if r.assigned, err = meter.Int64Gauge("ci_runner.capacity.assigned", metric.WithUnit("{job}"), metric.WithDescription("Authoritative assigned jobs by target pool.")); err != nil {
		return nil, err
	}
	if r.desired, err = meter.Int64Gauge("ci_runner.capacity.desired", metric.WithUnit("{worker}"), metric.WithDescription("Desired workers by target pool.")); err != nil {
		return nil, err
	}
	if r.workers, err = meter.Int64Gauge("ci_runner.workers", metric.WithUnit("{worker}"), metric.WithDescription("Managed workers by target pool and bounded lifecycle state.")); err != nil {
		return nil, err
	}
	if r.activeJobs, err = meter.Int64Gauge("ci_runner.jobs.active", metric.WithUnit("{job}"), metric.WithDescription("Active jobs by target pool.")); err != nil {
		return nil, err
	}
	if r.inventoryWorkers, err = meter.Int64Gauge("ci_runner.docker.inventory.workers", metric.WithUnit("{worker}"), metric.WithDescription("Workers present in the reconciled Docker inventory by target pool.")); err != nil {
		return nil, err
	}
	if r.assignmentGap, err = meter.Int64Gauge("ci_runner.accounting.assignment.gap", metric.WithUnit("{job}"), metric.WithDescription("GitHub assigned jobs minus locally visible busy or starting workers, floored at zero.")); err != nil {
		return nil, err
	}
	if r.transientLag, err = meter.Int64Gauge("ci_runner.accounting.transient_lag", metric.WithUnit("1"), metric.WithDescription("Whether short-job timing creates transientAccountingLag for a target pool.")); err != nil {
		return nil, err
	}
	if r.cpuPercent, err = meter.Float64Gauge("ci_runner.host.cpu.utilization", metric.WithUnit("%"), metric.WithDescription("Host CPU utilization percentage.")); err != nil {
		return nil, err
	}
	if r.availableMemory, err = meter.Int64Gauge("ci_runner.host.memory.available", metric.WithUnit("By"), metric.WithDescription("Available host physical memory.")); err != nil {
		return nil, err
	}
	if r.memoryHeadroom, err = meter.Int64Gauge("ci_runner.capacity.memory.headroom", metric.WithUnit("By"), metric.WithDescription("Memory headroom left unspent by the last plan under the active basis (static worker budget, or legacy host headroom).")); err != nil {
		return nil, err
	}
	if r.memoryAffordable, err = meter.Int64Gauge("ci_runner.capacity.memory.affordable", metric.WithUnit("{worker}"), metric.WithDescription("Additional workers the remaining memory headroom funds at the pool's effective worker profile.")); err != nil {
		return nil, err
	}
	if r.resourceGate, err = meter.Int64Gauge("ci_runner.gate.resource.blocked", metric.WithUnit("1"), metric.WithDescription("Whether resource admission is blocked.")); err != nil {
		return nil, err
	}
	if r.powerGate, err = meter.Int64Gauge("ci_runner.gate.power.blocked", metric.WithUnit("1"), metric.WithDescription("Whether power policy blocks admission.")); err != nil {
		return nil, err
	}
	if r.workerStarts, err = meter.Int64Counter("ci_runner.worker.starts", metric.WithUnit("{worker}"), metric.WithDescription("Worker start attempts by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.workerStartTime, err = meter.Float64Histogram("ci_runner.worker.start.duration", metric.WithUnit("s"), metric.WithDescription("Docker worker start duration by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.workerRegisters, err = meter.Int64Counter("ci_runner.worker.registrations", metric.WithUnit("{worker}"), metric.WithDescription("GitHub JIT worker registrations by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.workerRegisterTime, err = meter.Float64Histogram("ci_runner.worker.registration.duration", metric.WithUnit("s"), metric.WithDescription("GitHub JIT worker registration duration by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.workerFinalizes, err = meter.Int64Counter("ci_runner.worker.finalizations", metric.WithUnit("{worker}"), metric.WithDescription("Worker container finalizations by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.workerFinalizeTime, err = meter.Float64Histogram("ci_runner.worker.finalization.duration", metric.WithUnit("s"), metric.WithDescription("Worker artifact and container finalization duration by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.jobsStarted, err = meter.Int64Counter("ci_runner.jobs.started", metric.WithUnit("{job}"), metric.WithDescription("Durably indexed GitHub job-start events.")); err != nil {
		return nil, err
	}
	if r.jobStartLag, err = meter.Float64Histogram("ci_runner.jobs.start.visibility_lag", metric.WithUnit("s"), metric.WithDescription("Runner assignment to durable job-start observation lag.")); err != nil {
		return nil, err
	}
	if r.lifecycleEventTime, err = meter.Float64Gauge("ci_runner.worker.lifecycle.event.time", metric.WithUnit("s"), metric.WithDescription("Unix timestamp of the latest bounded worker lifecycle event.")); err != nil {
		return nil, err
	}
	if r.jobsCompleted, err = meter.Int64Counter("ci_runner.jobs.completed", metric.WithUnit("{job}"), metric.WithDescription("GitHub job completion events by bounded result.")); err != nil {
		return nil, err
	}
	if r.cancellations, err = meter.Int64Counter("ci_runner.cancellations", metric.WithUnit("{cancellation}"), metric.WithDescription("Expected cancellations by bounded source and classification.")); err != nil {
		return nil, err
	}
	if r.resourceEvidence, err = meter.Int64Counter("ci_runner.worker.resource.evidence", metric.WithUnit("{worker}"), metric.WithDescription("Terminal worker resource evidence records by bounded outcome.")); err != nil {
		return nil, err
	}
	if r.memoryPeak, err = meter.Int64Histogram("ci_runner.worker.memory.peak", metric.WithUnit("By"), metric.WithDescription("Terminal cgroup-v2 memory.peak by worker.")); err != nil {
		return nil, err
	}
	if r.memorySwapPeak, err = meter.Int64Histogram("ci_runner.worker.memory.swap.peak", metric.WithUnit("By"), metric.WithDescription("Terminal cgroup-v2 memory.swap.peak by worker.")); err != nil {
		return nil, err
	}
	if r.oomEvents, err = meter.Int64Counter("ci_runner.worker.memory.oom.events", metric.WithUnit("{event}"), metric.WithDescription("Terminal cgroup-v2 memory.events oom count.")); err != nil {
		return nil, err
	}
	if r.oomKillEvents, err = meter.Int64Counter("ci_runner.worker.memory.oom_kill.events", metric.WithUnit("{event}"), metric.WithDescription("Terminal cgroup-v2 memory.events oom_kill count.")); err != nil {
		return nil, err
	}
	if r.cpuPeriods, err = meter.Int64Histogram("ci_runner.worker.cpu.periods", metric.WithUnit("{period}"), metric.WithDescription("Terminal cgroup-v2 cpu.stat period count by worker.")); err != nil {
		return nil, err
	}
	if r.cpuThrottled, err = meter.Int64Histogram("ci_runner.worker.cpu.throttled.periods", metric.WithUnit("{period}"), metric.WithDescription("Terminal cgroup-v2 cpu.stat throttled period count by worker.")); err != nil {
		return nil, err
	}
	if r.cpuThrottledTime, err = meter.Float64Histogram("ci_runner.worker.cpu.throttled.duration", metric.WithUnit("s"), metric.WithDescription("Terminal cgroup-v2 cpu.stat throttled duration by worker.")); err != nil {
		return nil, err
	}
	if r.pidsPeak, err = meter.Int64Histogram("ci_runner.worker.pids.peak", metric.WithUnit("{process}"), metric.WithDescription("Terminal cgroup-v2 pids.peak by worker.")); err != nil {
		return nil, err
	}
	if r.ioRead, err = meter.Int64Histogram("ci_runner.worker.io.read", metric.WithUnit("By"), metric.WithDescription("Terminal aggregate cgroup-v2 io.stat read bytes by worker.")); err != nil {
		return nil, err
	}
	if r.ioWrite, err = meter.Int64Histogram("ci_runner.worker.io.write", metric.WithUnit("By"), metric.WithDescription("Terminal aggregate cgroup-v2 io.stat write bytes by worker.")); err != nil {
		return nil, err
	}
	return r, nil
}

func (r *recorder) BeginReconcile(ctx context.Context) (context.Context, func(ReconcileSnapshot, error)) {
	started := time.Now()
	ctx, span := r.tracer.Start(ctx, "controller.reconcile", trace.WithSpanKind(trace.SpanKindInternal))
	return ctx, func(snapshot ReconcileSnapshot, reconcileErr error) {
		result, unexpected := classifyReconcileResult(reconcileErr)
		attributes := []attribute.KeyValue{attribute.String("ci_runner.reconcile.result", result)}
		if snapshot.Phase != "" {
			attributes = append(attributes, attribute.String("ci_runner.phase", snapshot.Phase))
		}
		if snapshotHasTransientAccountingLag(snapshot) {
			attributes = append(attributes, attribute.String("ci_runner.accounting.classification", "transientAccountingLag"))
		}
		span.SetAttributes(attributes...)
		if unexpected {
			r.reconcileErrors.Add(ctx, 1)
			span.RecordError(reconcileErr)
			span.SetStatus(codes.Error, "reconciliation failed")
		} else if result == "canceled" {
			r.cancellations.Add(ctx, 1, metric.WithAttributes(
				attribute.String("ci_runner.cancellation.source", "controller"),
				attribute.String("ci_runner.cancellation.classification", "shutdown"),
			))
		}
		r.reconcileDuration.Record(ctx, time.Since(started).Seconds(), metric.WithAttributes(attribute.String("ci_runner.reconcile.result", result)))
		if snapshot.Valid {
			r.recordSnapshot(ctx, snapshot)
		}
		span.End()
	}
}

func classifyReconcileResult(err error) (string, bool) {
	if err == nil {
		return "succeeded", false
	}
	if errors.Is(err, context.Canceled) {
		return "canceled", false
	}
	return "failed", true
}

func (r *recorder) recordSnapshot(ctx context.Context, snapshot ReconcileSnapshot) {
	counts := make(map[string]map[string]int64, len(snapshot.Pools))
	active := make(map[string]int64, len(snapshot.Pools))
	for _, pool := range snapshot.Pools {
		attrs := metric.WithAttributes(attribute.String("ci_runner.pool.id", pool.ID))
		r.advertised.Record(ctx, int64(pool.Advertised), attrs)
		r.capacityAcknowledged.Record(ctx, boolInt64(pool.CapacityAcknowledged), attrs)
		if !pool.CapacityAcknowledged && pool.AcknowledgementPendingAgeValid {
			r.acknowledgementPendingAge.Record(ctx, max(0, pool.AcknowledgementPendingAge.Seconds()), attrs)
		}
		r.assigned.Record(ctx, int64(pool.Assigned), attrs)
		r.desired.Record(ctx, int64(pool.Desired), attrs)
		r.memoryAffordable.Record(ctx, int64(pool.AffordableWorkers), attrs)
		counts[pool.ID] = make(map[string]int64, len(workerStates))
	}
	for _, worker := range snapshot.Workers {
		if counts[worker.PoolID] == nil {
			continue
		}
		counts[worker.PoolID][worker.State]++
		if worker.State == "busy" {
			active[worker.PoolID]++
		}
	}
	for _, pool := range snapshot.Pools {
		for _, state := range workerStates {
			r.workers.Record(ctx, counts[pool.ID][state], metric.WithAttributes(
				attribute.String("ci_runner.pool.id", pool.ID),
				attribute.String("ci_runner.worker.state", state),
			))
		}
		r.activeJobs.Record(ctx, active[pool.ID], metric.WithAttributes(attribute.String("ci_runner.pool.id", pool.ID)))
		inventory := int64(0)
		for _, state := range workerStates {
			inventory += counts[pool.ID][state]
		}
		attrs := metric.WithAttributes(attribute.String("ci_runner.pool.id", pool.ID))
		r.inventoryWorkers.Record(ctx, inventory, attrs)
		locallyVisible := active[pool.ID] + counts[pool.ID]["starting"]
		gap := int64(pool.Assigned) - locallyVisible
		if gap < 0 {
			gap = 0
		}
		r.assignmentGap.Record(ctx, gap, attrs)
		r.transientLag.Record(ctx, boolInt64(gap > 0), attrs)
	}
	r.cpuPercent.Record(ctx, snapshot.CPUPercent)
	available := snapshot.AvailableMemoryBytes
	if available > math.MaxInt64 {
		available = math.MaxInt64
	}
	r.availableMemory.Record(ctx, int64(available))
	r.memoryHeadroom.Record(ctx, clampUint64(snapshot.MemoryHeadroomBytes))
	r.resourceGate.Record(ctx, boolInt64(snapshot.ResourceGateBlocked))
	r.powerGate.Record(ctx, boolInt64(snapshot.PowerGateBlocked))
	if snapshot.CheckpointAgeValid {
		r.checkpointAge.Record(ctx, max(0, snapshot.CheckpointAge.Seconds()))
	}
}

func snapshotHasTransientAccountingLag(snapshot ReconcileSnapshot) bool {
	visible := make(map[string]int, len(snapshot.Pools))
	for _, worker := range snapshot.Workers {
		if worker.State == "busy" || worker.State == "starting" {
			visible[worker.PoolID]++
		}
	}
	for _, pool := range snapshot.Pools {
		if pool.Assigned > visible[pool.ID] {
			return true
		}
	}
	return false
}

func (r *recorder) WorkerRegistered(ctx context.Context, poolID, tier string, duration time.Duration, outcome WorkerStartOutcome) {
	if poolID == "" {
		return
	}
	attrs := []attribute.KeyValue{
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", normalizeResourceTier(tier)),
		attribute.String("ci_runner.worker.registration.outcome", string(outcome)),
	}
	r.workerRegisters.Add(ctx, 1, metric.WithAttributes(attrs...))
	r.workerRegisterTime.Record(ctx, max(0, duration.Seconds()), metric.WithAttributes(attrs...))
	r.recordLifecycleEventTime(ctx, poolID, tier, "registered", string(outcome))
	trace.SpanFromContext(ctx).AddEvent("worker.registered", trace.WithAttributes(attrs...))
}

func (r *recorder) WorkerStarted(ctx context.Context, poolID, tier string, duration time.Duration, outcome WorkerStartOutcome) {
	if poolID == "" {
		return
	}
	attrs := []attribute.KeyValue{
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", normalizeResourceTier(tier)),
		attribute.String("ci_runner.worker.start.outcome", string(outcome)),
	}
	r.workerStarts.Add(ctx, 1, metric.WithAttributes(attrs...))
	r.workerStartTime.Record(ctx, max(0, duration.Seconds()), metric.WithAttributes(attrs...))
	r.recordLifecycleEventTime(ctx, poolID, tier, "started", string(outcome))
	trace.SpanFromContext(ctx).AddEvent("worker.started", trace.WithAttributes(attrs...))
	if outcome == WorkerStartCanceled {
		r.cancellations.Add(ctx, 1, metric.WithAttributes(
			attribute.String("ci_runner.cancellation.source", "worker_start"),
			attribute.String("ci_runner.cancellation.classification", "controller_context"),
		))
	}
}

func (r *recorder) WorkerFinalized(ctx context.Context, poolID string, value WorkerFinalization) {
	if poolID == "" {
		return
	}
	outcome := ClassifyWorkerFinalization(value)
	tier := normalizeResourceTier(value.ResourceTier)
	baseAttributes := []attribute.KeyValue{
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", tier),
		attribute.String("ci_runner.worker.finalization.outcome", string(outcome)),
	}
	r.workerFinalizes.Add(ctx, 1, metric.WithAttributes(baseAttributes...))
	r.workerFinalizeTime.Record(ctx, max(0, value.Duration.Seconds()), metric.WithAttributes(baseAttributes...))
	r.recordLifecycleEventTime(ctx, poolID, tier, "finalized", string(outcome))
	if outcome == WorkerFinalizationCanceled {
		r.cancellations.Add(ctx, 1, metric.WithAttributes(
			attribute.String("ci_runner.cancellation.source", "worker_finalization"),
			attribute.String("ci_runner.cancellation.classification", "controller_context"),
		))
	}
	if value.RecordResourceEvidence {
		r.recordWorkerResourceEvidence(ctx, poolID, tier, outcome, value.ResourceEvidence)
	}
}

func (r *recorder) ObserveJobStarted(ctx context.Context, poolID string, visibilityLag time.Duration) {
	if poolID == "" {
		return
	}
	attrs := []attribute.KeyValue{attribute.String("ci_runner.pool.id", poolID)}
	r.jobsStarted.Add(ctx, 1, metric.WithAttributes(attrs...))
	r.jobStartLag.Record(ctx, max(0, visibilityLag.Seconds()), metric.WithAttributes(attrs...))
	r.recordLifecycleEventTime(ctx, poolID, "unknown", "job_started", "observed")
	trace.SpanFromContext(ctx).AddEvent("job.started", trace.WithAttributes(attrs...))
}

func (r *recorder) recordLifecycleEventTime(ctx context.Context, poolID, tier, event, outcome string) {
	r.lifecycleEventTime.Record(ctx, float64(time.Now().UnixNano())/float64(time.Second), metric.WithAttributes(
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", normalizeResourceTier(tier)),
		attribute.String("ci_runner.worker.lifecycle.event", event),
		attribute.String("ci_runner.worker.lifecycle.outcome", outcome),
	))
}

func (r *recorder) recordWorkerResourceEvidence(ctx context.Context, poolID, tier string, finalizationOutcome WorkerFinalizationOutcome, evidence *WorkerResourceEvidence) {
	status := "unavailable"
	if evidence != nil {
		status = normalizeResourceOutcome(evidence.Status)
	}
	evidenceAttributes := []attribute.KeyValue{
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", tier),
		attribute.String("ci_runner.worker.resource.outcome", status),
	}
	r.resourceEvidence.Add(ctx, 1, metric.WithAttributes(evidenceAttributes...))
	if evidence == nil || status == "missing" || status == "unavailable" || status == "invalid" {
		return
	}
	attrs := metric.WithAttributes(
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.worker.resource.tier", tier),
		attribute.String("ci_runner.worker.finalization.outcome", string(finalizationOutcome)),
	)
	if !slices.Contains(evidence.Missing, "memory.peak") {
		r.memoryPeak.Record(ctx, clampUint64(evidence.MemoryPeakBytes), attrs)
	}
	if !slices.Contains(evidence.Missing, "memory.swap.peak") {
		r.memorySwapPeak.Record(ctx, clampUint64(evidence.MemorySwapPeakBytes), attrs)
	}
	if !slices.Contains(evidence.Missing, "memory.events.oom") {
		r.oomEvents.Add(ctx, clampUint64(evidence.OOMEvents), attrs)
	}
	if !slices.Contains(evidence.Missing, "memory.events.oom_kill") {
		r.oomKillEvents.Add(ctx, clampUint64(evidence.OOMKillEvents), attrs)
	}
	if !slices.Contains(evidence.Missing, "cpu.stat.nr_periods") {
		r.cpuPeriods.Record(ctx, clampUint64(evidence.CPUPeriods), attrs)
	}
	if !slices.Contains(evidence.Missing, "cpu.stat.nr_throttled") {
		r.cpuThrottled.Record(ctx, clampUint64(evidence.CPUThrottledPeriods), attrs)
	}
	if !slices.Contains(evidence.Missing, "cpu.stat.throttled_usec") {
		r.cpuThrottledTime.Record(ctx, float64(evidence.CPUThrottledMicroseconds)/1_000_000, attrs)
	}
	if !slices.Contains(evidence.Missing, "pids.peak") {
		r.pidsPeak.Record(ctx, clampUint64(evidence.PIDsPeak), attrs)
	}
	if !slices.Contains(evidence.Missing, "io.stat") {
		r.ioRead.Record(ctx, clampUint64(evidence.IOReadBytes), attrs)
		r.ioWrite.Record(ctx, clampUint64(evidence.IOWriteBytes), attrs)
	}
}

func normalizeResourceTier(value string) string {
	switch value {
	case "default", "target_override", "unknown":
		return value
	default:
		return "unknown"
	}
}

func normalizeResourceOutcome(value string) string {
	switch value {
	case "complete", "partial", "missing", "unavailable", "invalid":
		return value
	default:
		return "invalid"
	}
}

func clampUint64(value uint64) int64 {
	if value > math.MaxInt64 {
		return math.MaxInt64
	}
	return int64(value)
}

func (r *recorder) ObserveJobCompleted(ctx context.Context, poolID, result string, assigned bool) {
	if poolID == "" {
		return
	}
	normalized := normalizeJobResult(result)
	r.jobsCompleted.Add(ctx, 1, metric.WithAttributes(
		attribute.String("ci_runner.pool.id", poolID),
		attribute.String("ci_runner.job.result", normalized),
	))
	if normalized != "canceled" {
		return
	}
	classification := "before_assignment"
	if assigned {
		classification = "assigned"
	}
	r.cancellations.Add(ctx, 1, metric.WithAttributes(
		attribute.String("ci_runner.cancellation.source", "github_job"),
		attribute.String("ci_runner.cancellation.classification", classification),
	))
}

func normalizeJobResult(result string) string {
	switch strings.ToLower(strings.TrimSpace(result)) {
	case "succeeded", "success":
		return "succeeded"
	case "failed", "failure":
		return "failed"
	case "canceled", "cancelled":
		return "canceled"
	case "skipped":
		return "skipped"
	default:
		return "other"
	}
}

func boolInt64(value bool) int64 {
	if value {
		return 1
	}
	return 0
}
