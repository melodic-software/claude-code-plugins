package controller

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/melodic-software/ci-runner/internal/buildinfo"
	"github.com/melodic-software/ci-runner/internal/config"
	"github.com/melodic-software/ci-runner/internal/model"
	"github.com/melodic-software/ci-runner/internal/scaleset"
	statepkg "github.com/melodic-software/ci-runner/internal/state"
)

var ErrUnsafeObservedState = errors.New("observed state could not be loaded; refusing to reconcile persistent scale-set identities")

var (
	errReconcileInputsChanged = errors.New("reconciliation safety inputs changed")
	errShutdownRequested      = errors.New("controller shutdown requested")
)

type Dependencies struct {
	ScaleSets ScaleSetClient
	Workers   WorkerRuntime
	Desktop   DesktopManager
	Power     PowerMonitor
	Resources ResourceMonitor
	State     StateStore
	Jobs      JobLookup
	Clock     Clock
	Logs      LogSink
}

type Reconciler struct {
	config  config.Config
	version string
	deps    Dependencies

	// stepMu serializes side effects without blocking local control-plane status
	// requests. stateMu protects only short-lived in-memory state and must never
	// be held across an adapter call or listener poll.
	stepMu  sync.Mutex
	stateMu sync.Mutex

	backoff           BackoffPolicy
	watchInterval     time.Duration
	currentStepCancel context.CancelCauseFunc
	drainCapacity     map[string]int
	sequence          uint64
	shuttingDown      bool
}

type ReconcileResult struct {
	Observed model.ObservedState
	Plan     Plan
}

func NewReconciler(cfg config.Config, version string, deps Dependencies) (*Reconciler, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	if deps.ScaleSets == nil || deps.Workers == nil || deps.Desktop == nil || deps.Power == nil || deps.Resources == nil || deps.State == nil || deps.Jobs == nil || deps.Clock == nil {
		return nil, errors.New("controller dependencies must not be nil")
	}
	if deps.Logs == nil {
		deps.Logs = DiscardLogSink{}
	}
	if version == "" {
		version = buildinfo.Version
	}
	watchInterval := cfg.Controller.ReconcileInterval.Duration
	if watchInterval <= 0 || watchInterval > time.Second {
		watchInterval = time.Second
	}
	return &Reconciler{
		config: cfg, version: version, deps: deps,
		backoff: BackoffPolicy{
			Initial: cfg.GitHub.Retry.Initial.Duration, Maximum: cfg.GitHub.Retry.Maximum.Duration,
			Multiplier: cfg.GitHub.Retry.Multiplier, JitterRatio: cfg.GitHub.Retry.JitterRatio,
			MaxAttempts: cfg.GitHub.Retry.MaxAttempts, Jitter: cryptoJitter,
		},
		watchInterval: watchInterval,
		drainCapacity: make(map[string]int),
	}, nil
}

func (r *Reconciler) SetBackoffForTest(policy BackoffPolicy) error {
	if err := policy.validate(); err != nil {
		return err
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	r.backoff = policy
	return nil
}

func (r *Reconciler) setWatchIntervalForTest(interval time.Duration) error {
	if interval <= 0 {
		return errors.New("safety watch interval must be positive")
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	r.watchInterval = interval
	return nil
}

// Step performs one serialized reconciliation. Polling scale-set statistics
// (and therefore advertising capacity) happens before any idle worker removal.
func (r *Reconciler) Step(ctx context.Context) (ReconcileResult, error) {
	r.stepMu.Lock()
	defer r.stepMu.Unlock()

	for {
		if err := ctx.Err(); err != nil {
			return ReconcileResult{}, err
		}
		stepCtx, cancel := context.WithCancelCause(ctx)
		r.stateMu.Lock()
		r.currentStepCancel = cancel
		r.stateMu.Unlock()

		result, err := r.step(stepCtx, cancel)
		cause := context.Cause(stepCtx)
		r.stateMu.Lock()
		r.currentStepCancel = nil
		r.stateMu.Unlock()
		cancel(nil)

		if errors.Is(cause, errReconcileInputsChanged) && ctx.Err() == nil {
			// Re-run immediately so the changed desired/power state is advertised;
			// waiting for the normal reconciliation interval could leave stale
			// nonzero capacity visible for an entire long poll.
			continue
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ReconcileResult{}, ctxErr
		}
		if cause != nil && err == nil {
			err = cause
		}
		return result, err
	}
}

func (r *Reconciler) step(ctx context.Context, cancel context.CancelCauseFunc) (ReconcileResult, error) {
	if err := ctx.Err(); err != nil {
		return ReconcileResult{}, err
	}

	now := r.deps.Clock.Now().UTC()
	desired, err := r.deps.State.LoadDesired(ctx)
	var desiredLoadErr error
	if errors.Is(err, statepkg.ErrNotFound) {
		// Missing local intent fails safe. Provisioning may create an initial
		// desired file, but it must never overwrite one after installation.
		desired = model.DesiredState{SchemaVersion: 1, Mode: model.ModeDisabled, UpdatedAt: now}
		if err := r.deps.State.SaveDesired(ctx, desired); err != nil {
			return ReconcileResult{}, fmt.Errorf("initialize desired state: %w", err)
		}
	} else if err != nil {
		// A desired-state read failure must fail capacity closed. Preserve the
		// file as evidence, but continue with transient disabled intent so any
		// existing listener can acknowledge zero capacity.
		desiredLoadErr = fmt.Errorf("load desired state: %w", err)
		desired = model.DesiredState{SchemaVersion: 1, Mode: model.ModeDisabled, UpdatedAt: now}
	}
	if r.isShuttingDown() {
		// Process replacement drains transiently without changing the user's
		// persisted intent. The replacement process can resume that intent.
		desired.Mode = model.ModeDisabled
		desired.TemporaryCapacityOverride = nil
	}

	previous, err := r.deps.State.LoadObserved(ctx)
	recoveryOnly := false
	var observedLoadErr error
	if err != nil && !errors.Is(err, statepkg.ErrNotFound) {
		quarantiner, ok := r.deps.State.(interface{ QuarantineObserved(context.Context) error })
		if !ok {
			return ReconcileResult{}, errors.Join(ErrUnsafeObservedState, err)
		}
		if quarantineErr := quarantiner.QuarantineObserved(ctx); quarantineErr != nil {
			return ReconcileResult{}, errors.Join(ErrUnsafeObservedState, err, quarantineErr)
		}
		// Preserve the corrupt source until SaveObserved atomically replaces it,
		// then reconstruct the exact configured scale set solely to advertise
		// zero. No worker or Desktop lifecycle mutation is allowed in this pass.
		observedLoadErr = err
		previous = model.ObservedState{}
		recoveryOnly = true
		desired.Mode = model.ModeDisabled
		desired.TemporaryCapacityOverride = nil
	}

	var operationErrors []error
	var operationProblems []model.Problem
	record := func(code, message, poolID string, retryable bool, err error) {
		operationProblems = append(operationProblems, problem(now, code, message, poolID, retryable))
		if err != nil {
			operationErrors = append(operationErrors, err)
		}
		_ = r.deps.Logs.Write(ctx, LogEvent{At: now, Code: code, Message: message, PoolID: poolID})
	}
	note := func(code, message, poolID string) {
		_ = r.deps.Logs.Write(ctx, LogEvent{At: now, Code: code, Message: message, PoolID: poolID})
	}
	if desiredLoadErr != nil {
		record("desired-state-error", "desired state could not be read; capacity is held at zero", "", true, desiredLoadErr)
	}
	if observedLoadErr != nil {
		record("observed-state-recovered", "corrupt observed state was quarantined; exact configured listeners are held at zero and lifecycle mutations are suspended", "", false, observedLoadErr)
	}

	observationFailed := false
	power, powerErr := r.deps.Power.Snapshot(ctx)
	if powerErr != nil {
		observationFailed = true
		record("power-monitor-error", "power observation failed; new work is blocked", "", true, powerErr)
	}
	watchContext, stopWatch := context.WithCancel(ctx)
	watchDone := make(chan struct{})
	go func() {
		defer close(watchDone)
		r.watchSafetyInputs(watchContext, desired, power, cancel, recoveryOnly || desiredLoadErr != nil || powerErr != nil || r.isShuttingDown())
	}()
	defer func() {
		stopWatch()
		<-watchDone
	}()
	desktop, desktopErr := r.deps.Desktop.Status(ctx)
	desktopStatusKnown := desktopErr == nil
	if desktopErr != nil {
		observationFailed = true
		record("desktop-status-error", "Docker Desktop status failed; new work is blocked", "", true, desktopErr)
	}

	// Desktop lifecycle is a host prerequisite, not a worker-admission decision.
	// A known stopped/unreachable engine cannot answer Docker inventory calls, so
	// enabled mode must bootstrap it before resource admission or inventory. An
	// unknown Desktop status and an unknown power state still fail closed.
	if desired.Mode == model.ModeEnabled && desktopStatusKnown && powerErr == nil {
		_, powerAllowed := evaluatePowerGate(previous.PowerGate, power, r.config.Power, now)
		if powerAllowed && (!desktop.DesktopRunning || !desktop.EngineReachable) {
			if startErr := r.deps.Desktop.Start(ctx, r.config.DockerDesktop.StartTimeout.Duration); startErr != nil {
				observationFailed = true
				record("desktop-start-error", "Docker Desktop did not start within the configured policy", "", true, startErr)
			} else if refreshed, statusErr := r.deps.Desktop.Status(ctx); statusErr != nil {
				desktopStatusKnown = false
				observationFailed = true
				record("desktop-start-status-error", "Docker Desktop status could not be verified after startup", "", true, statusErr)
			} else {
				desktop = refreshed
				if !desktop.DesktopRunning || !desktop.EngineReachable {
					observationFailed = true
					verificationErr := errors.New("Docker Desktop remained stopped or its engine remained unreachable after startup")
					record("desktop-start-verification-error", "Docker Desktop did not reach a usable state after startup", "", true, verificationErr)
				}
			}
		}
	}

	resources, resourceErr := r.deps.Resources.Snapshot(ctx)
	if resourceErr != nil {
		observationFailed = true
		record("resource-monitor-error", "resource observation failed; new work is blocked", "", true, resourceErr)
	}
	workers := []model.Worker(nil)
	if mayHaveManagedWorkers(desktop, desktopStatusKnown) {
		latest, listErr := r.deps.Workers.List(ctx)
		if listErr != nil {
			observationFailed = true
			record("worker-inventory-error", "managed-worker inventory failed; new work is blocked", "", true, listErr)
		} else {
			workers = latest
		}
	}
	if observationFailed {
		resources = model.ResourceSnapshot{} // invalid observation fails closed in BuildPlan
	}
	jobStateKnown := true
	if enriched, lookupErr := r.enrichWorkerJobs(ctx, workers); lookupErr != nil {
		jobStateKnown = false
		observationFailed = true
		resources = model.ResourceSnapshot{}
		record("job-index-error", "durable job lifecycle state could not be read; new work and automatic retirement are blocked", "", true, lookupErr)
	} else {
		workers = enriched
	}

	previousPools := make(map[string]model.PoolObservation, len(previous.Pools))
	for _, pool := range previous.Pools {
		previousPools[pool.ID] = pool
	}
	identities := make(map[string]scaleset.Identity, len(r.config.GitHub.Targets))
	pools := make([]PoolSnapshot, 0, len(r.config.GitHub.Targets))
	for _, target := range r.config.GitHub.Targets {
		var prior *scaleset.Identity
		if saved, ok := previousPools[target.ID]; ok && saved.ScaleSetID > 0 && saved.ListenerID != "" {
			value := scaleset.Identity{ScaleSetID: saved.ScaleSetID, ListenerID: saved.ListenerID}
			prior = &value
		}
		identity, ensureErr := r.ensure(ctx, target, prior)
		if ensureErr != nil {
			record("scale-set-ensure-error", safeScaleSetMessage("ensure", ensureErr), target.ID, scaleset.Retryable(ensureErr), ensureErr)
			pools = append(pools, PoolSnapshot{TargetID: target.ID})
			continue
		}
		identities[target.ID] = identity
		assigned := previousPools[target.ID].TotalAssignedJobs
		drainCapacity := previousPools[target.ID].DrainServiceCapacity
		if drainCapacity == 0 && previousPools[target.ID].MaxCapacity > 0 {
			drainCapacity = previousPools[target.ID].MaxCapacity
		}
		if remembered := r.rememberedDrainCapacity(target.ID); remembered > drainCapacity {
			drainCapacity = remembered
		}
		pools = append(pools, PoolSnapshot{
			TargetID: target.ID, Identity: identity, TotalAssignedJobs: assigned,
			DrainServiceCapacity: drainCapacity, Ready: true,
		})
	}

	// Compute capacity from the last authoritative statistics, then send that
	// capacity with this poll. Newly returned statistics drive worker changes
	// now and the next poll's capacity, avoiding an unsupported reservation API.
	provisional := BuildPlan(PlanInput{
		Config: r.config, Desired: desired, Previous: previous, Pools: pools,
		Workers: workers, Resources: resources, Power: power, Desktop: desktop, Now: now,
	})
	type pollResult struct {
		index      int
		stats      scaleset.Statistics
		identity   scaleset.Identity
		advertised int
		err        error
	}
	pollResults := make(chan pollResult, len(pools))
	acknowledgedCapacity := make(map[string]int, len(pools))
	capacityAcknowledged := make(map[string]bool, len(pools))
	zeroAcknowledged := make(map[string]bool, len(pools))
	zeroConfirmations := make(map[string]int, len(pools))
	var polls sync.WaitGroup
	for index := range pools {
		pool := pools[index]
		if !pool.Ready {
			continue
		}
		polls.Add(1)
		go func() {
			defer polls.Done()
			advertised := provisional.AdvertisedCapacity[pool.TargetID]
			stats, identity, statsErr := r.statistics(ctx, r.target(pool.TargetID), pool.Identity, advertised)
			pollResults <- pollResult{index: index, stats: stats, identity: identity, advertised: advertised, err: statsErr}
		}()
	}
	polls.Wait()
	close(pollResults)
	for result := range pollResults {
		pool := &pools[result.index]
		if result.err != nil {
			pool.Ready = false
			record("scale-set-statistics-error", safeScaleSetMessage("poll", result.err), pool.TargetID, scaleset.Retryable(result.err), result.err)
			continue
		}
		pool.Identity = result.identity
		identities[pool.TargetID] = result.identity
		pool.TotalAssignedJobs = result.stats.TotalAssignedJobs
		if result.advertised > 0 {
			pool.DrainServiceCapacity = result.advertised
			r.rememberDrainCapacity(pool.TargetID, result.advertised)
		} else if result.stats.TotalAssignedJobs == 0 {
			pool.DrainServiceCapacity = 0
			r.rememberDrainCapacity(pool.TargetID, 0)
		}
		acknowledgedCapacity[pool.TargetID] = result.advertised
		capacityAcknowledged[pool.TargetID] = true
		zeroAcknowledged[pool.TargetID] = result.advertised == 0
		if result.advertised == 0 && result.stats.TotalAssignedJobs == 0 {
			zeroConfirmations[pool.TargetID] = 1
			prior := previousPools[pool.TargetID]
			if prior.CapacityAcknowledged && prior.MaxCapacity == 0 && prior.TotalAssignedJobs == 0 && prior.ZeroCapacityConfirmations > 0 {
				zeroConfirmations[pool.TargetID] = minInt(2, prior.ZeroCapacityConfirmations+1)
			}
		}
	}
	if cause := context.Cause(ctx); cause != nil {
		return ReconcileResult{}, cause
	}

	// Refresh after capacity was advertised. This is important during drain:
	// an assignment accepted just before zero capacity must be observed as busy
	// and protected before any conditional removal is attempted.
	if mayHaveManagedWorkers(desktop, desktopStatusKnown) {
		if latest, listErr := r.deps.Workers.List(ctx); listErr != nil {
			observationFailed = true
			resources = model.ResourceSnapshot{}
			record("worker-refresh-error", "managed-worker refresh failed after capacity update; new work is blocked", "", true, listErr)
		} else if enriched, lookupErr := r.enrichWorkerJobs(ctx, latest); lookupErr != nil {
			jobStateKnown = false
			observationFailed = true
			resources = model.ResourceSnapshot{}
			record("job-index-refresh-error", "durable job lifecycle state could not be refreshed after the capacity update; automatic retirement is blocked", "", true, lookupErr)
		} else {
			workers = enriched
		}
	}

	plan := BuildPlan(PlanInput{
		Config: r.config, Desired: desired, Previous: previous, Pools: pools,
		Workers: workers, Resources: resources, Power: power, Desktop: desktop, Now: now,
	})
	if recoveryOnly {
		plan.Start = nil
		plan.Remove = nil
		plan.StartDesktop = false
		plan.StopDesktop = false
		plan.ShutdownWSL = false
	}

	if plan.StartDesktop {
		if startErr := r.deps.Desktop.Start(ctx, r.config.DockerDesktop.StartTimeout.Duration); startErr != nil {
			record("desktop-start-error", "Docker Desktop did not start within the configured policy", "", true, startErr)
		}
	}

	seenRemoval := map[string]struct{}{}
	for _, worker := range plan.Remove {
		if _, duplicate := seenRemoval[worker.ID]; duplicate {
			continue
		}
		seenRemoval[worker.ID] = struct{}{}
		if worker.State == model.WorkerBusy {
			record("busy-worker-removal-refused", "controller policy refused to remove a busy worker", worker.PoolID, false, nil)
			continue
		}
		requiredCapacity, configuredPool := plan.AdvertisedCapacity[worker.PoolID]
		if worker.State != model.WorkerExited && !configuredPool {
			record("worker-retirement-pool-unknown", "automatic retirement was refused because the worker pool is not configured and cannot be quiesced", worker.PoolID, false, nil)
			continue
		}
		if worker.State != model.WorkerExited && !jobStateKnown {
			record("worker-retirement-job-state-unknown", "automatic retirement was refused because durable job state is unavailable", worker.PoolID, true, nil)
			continue
		}
		if configuredPool && !capacityAcknowledged[worker.PoolID] {
			record("worker-removal-capacity-unconfirmed", "idle worker removal was deferred because the listener did not acknowledge the capacity update", worker.PoolID, true, nil)
			continue
		}
		if configuredPool && acknowledgedCapacity[worker.PoolID] != requiredCapacity {
			record("worker-removal-capacity-stale", "idle worker removal was deferred until the listener acknowledges the current planned capacity", worker.PoolID, true, nil)
			continue
		}
		if worker.State != model.WorkerExited && configuredPool && requiredCapacity != 0 {
			record("worker-retirement-quiescence-required", "automatic retirement was deferred because the pool still advertises assignment headroom", worker.PoolID, false, nil)
			continue
		}
		if configuredPool && requiredCapacity == 0 && !zeroAcknowledged[worker.PoolID] {
			note("worker-removal-zero-unconfirmed", "idle worker removal was deferred until the listener acknowledges zero capacity", worker.PoolID)
			continue
		}
		pool := findPool(pools, worker.PoolID)
		if worker.State != model.WorkerExited && (pool.TotalAssignedJobs != 0 || zeroConfirmations[worker.PoolID] < 2) {
			note("worker-retirement-zero-stability-unconfirmed", "automatic retirement was deferred until two capacity-zero polls report no assigned jobs", worker.PoolID)
			continue
		}
		if worker.State != model.WorkerExited {
			if worker.RunnerID <= 0 {
				record("worker-retirement-runner-id-missing", "automatic retirement was refused because the managed worker has no persisted GitHub runner ID", worker.PoolID, false, nil)
				continue
			}
			if removeRunnerErr := r.deregisterRunner(ctx, worker.PoolID, worker.RunnerID); removeRunnerErr != nil {
				record("runner-deregistration-error", safeScaleSetMessage("deregister quiesced runner", removeRunnerErr), worker.PoolID, scaleset.Retryable(removeRunnerErr), removeRunnerErr)
				continue
			}
		}
		removed, removeErr := r.deps.Workers.RemoveIfIdle(ctx, worker.ID)
		if removeErr != nil {
			record("worker-remove-error", "idle worker removal failed", worker.PoolID, true, removeErr)
			continue
		}
		if !removed {
			record("worker-became-busy", "worker acquired work during drain and was preserved", worker.PoolID, false, nil)
		}
	}

	reservedStarts := 0
startLoop:
	for _, decision := range plan.Start {
		identity, ok := identities[decision.PoolID]
		if !ok {
			continue
		}
		for count := 0; count < decision.Count; count++ {
			if err := ctx.Err(); err != nil {
				operationErrors = append(operationErrors, err)
				break
			}
			allowed, safetyChanged, admissionErr := r.freshStartAllowed(ctx, decision.PoolID, pools, previous, desired, power, resources, desktop, reservedStarts)
			if admissionErr != nil || safetyChanged {
				cancel(errReconcileInputsChanged)
				return ReconcileResult{}, errReconcileInputsChanged
			}
			if !allowed {
				break startLoop
			}
			name := r.nextRunnerName(decision.PoolID, now)
			jit, jitErr := RetryValue(ctx, r.deps.Clock, r.backoffPolicy(), scaleset.Retryable, func(callCtx context.Context) (scaleset.JITConfig, error) {
				return r.deps.ScaleSets.CreateJITConfig(callCtx, identity, name)
			})
			if jitErr != nil {
				record("jit-config-error", safeScaleSetMessage("create JIT configuration", jitErr), decision.PoolID, scaleset.Retryable(jitErr), jitErr)
				break
			}
			// JIT creation is a network operation. Re-read every safety and
			// admission input again immediately before the irreversible container
			// start so a stale pre-JIT snapshot cannot admit work.
			allowed, safetyChanged, admissionErr = r.freshStartAllowed(ctx, decision.PoolID, pools, previous, desired, power, resources, desktop, reservedStarts)
			if admissionErr != nil || safetyChanged {
				cleanupContext, cleanupCancel := context.WithTimeout(context.WithoutCancel(ctx), r.config.GitHub.RequestTimeout.Duration)
				cleanupErr := r.deregisterRunner(cleanupContext, decision.PoolID, jit.RunnerID())
				cleanupCancel()
				if cleanupErr != nil {
					_ = r.deps.Logs.Write(context.Background(), LogEvent{At: r.deps.Clock.Now().UTC(), Code: "unused-jit-runner-cleanup-error", Message: safeScaleSetMessage("deregister unused JIT runner", cleanupErr), PoolID: decision.PoolID})
				}
				cancel(errReconcileInputsChanged)
				return ReconcileResult{}, errReconcileInputsChanged
			}
			if !allowed {
				cleanupContext, cleanupCancel := context.WithTimeout(context.WithoutCancel(ctx), r.config.GitHub.RequestTimeout.Duration)
				cleanupErr := r.deregisterRunner(cleanupContext, decision.PoolID, jit.RunnerID())
				cleanupCancel()
				if cleanupErr != nil {
					record("unused-jit-runner-cleanup-error", safeScaleSetMessage("deregister unused JIT runner", cleanupErr), decision.PoolID, scaleset.Retryable(cleanupErr), cleanupErr)
				}
				break startLoop
			}
			_, startErr := r.deps.Workers.Start(ctx, StartWorkerRequest{
				PoolID: decision.PoolID, Name: name, JITConfig: jit, Limits: r.config.Resources.Worker,
			})
			if startErr != nil {
				// Start is intentionally not retried: it may have created a running
				// container before returning an error. The next inventory reconciles it.
				record("worker-start-error", "one-job worker start failed; inventory will reconcile before retry", decision.PoolID, true, startErr)
				if !RunnerStartMayBeActive(startErr) {
					cleanupContext, cleanupCancel := context.WithTimeout(context.WithoutCancel(ctx), r.config.GitHub.RequestTimeout.Duration)
					cleanupErr := r.deregisterRunner(cleanupContext, decision.PoolID, jit.RunnerID())
					cleanupCancel()
					if cleanupErr != nil {
						record("failed-start-runner-cleanup-error", safeScaleSetMessage("deregister runner after pre-start failure", cleanupErr), decision.PoolID, scaleset.Retryable(cleanupErr), cleanupErr)
					}
				}
				break
			}
			reservedStarts++
		}
	}

	if plan.StopDesktop || plan.ShutdownWSL {
		if !allTargetsStablyZero(r.config.GitHub.Targets, zeroAcknowledged, zeroConfirmations) {
			note("gaming-zero-capacity-unconfirmed", "Docker and WSL shutdown was deferred until every listener has two zero-capacity, zero-assignment confirmations", "")
			plan.StopDesktop = false
			plan.ShutdownWSL = false
		}
	}
	if plan.StopDesktop || plan.ShutdownWSL {
		var currentWorkers []model.Worker
		var inventoryErr error
		if mayHaveManagedWorkers(desktop, desktopStatusKnown) {
			currentWorkers, inventoryErr = r.deps.Workers.List(ctx)
		}
		if inventoryErr != nil {
			record("gaming-preflight-error", "gaming shutdown was deferred because worker status could not be verified", "", true, inventoryErr)
		} else if enriched, lookupErr := r.enrichWorkerJobs(ctx, currentWorkers); lookupErr != nil {
			record("gaming-job-index-error", "gaming shutdown was deferred because durable job lifecycle state could not be verified", "", true, lookupErr)
		} else if containsActiveWorker(enriched) {
			record("gaming-active-race", "gaming shutdown was deferred because a managed worker is still active", "", false, nil)
		} else {
			if plan.StopDesktop {
				if stopErr := r.deps.Desktop.Stop(ctx, r.config.DockerDesktop.StopTimeout.Duration); stopErr != nil {
					record("desktop-stop-error", "Docker Desktop did not stop within the configured policy", "", true, stopErr)
				}
			}
			if plan.ShutdownWSL {
				if shutdownErr := r.deps.Desktop.ShutdownAllWSL(ctx); shutdownErr != nil {
					record("wsl-shutdown-error", "one or more WSL distributions remain running", "", true, shutdownErr)
				}
			}
		}
	}

	if latest, statusErr := r.deps.Desktop.Status(ctx); statusErr == nil {
		desktop = latest
		desktopStatusKnown = true
	} else {
		desktopStatusKnown = false
		record("desktop-final-status-error", "final Docker Desktop status failed", "", true, statusErr)
	}
	if mayHaveManagedWorkers(desktop, desktopStatusKnown) {
		if latest, listErr := r.deps.Workers.List(ctx); listErr == nil {
			if enriched, lookupErr := r.enrichWorkerJobs(ctx, latest); lookupErr != nil {
				record("job-index-final-error", "final durable job lifecycle state could not be read", "", true, lookupErr)
			} else {
				workers = enriched
			}
		} else {
			record("worker-final-inventory-error", "final managed-worker inventory failed", "", true, listErr)
		}
	} else {
		workers = nil
	}

	postPlan := BuildPlan(PlanInput{
		Config: r.config, Desired: desired, Previous: previous, Pools: pools,
		Workers: workers, Resources: resources, Power: power, Desktop: desktop, Now: now,
	})
	observedPools := make([]model.PoolObservation, 0, len(r.config.GitHub.Targets))
	for _, target := range r.config.GitHub.Targets {
		pool := findPool(pools, target.ID)
		actualCapacity := previousPools[target.ID].MaxCapacity
		if capacityAcknowledged[target.ID] {
			actualCapacity = acknowledgedCapacity[target.ID]
		}
		observedPools = append(observedPools, model.PoolObservation{
			ID: target.ID, ScaleSetID: pool.Identity.ScaleSetID, ListenerID: pool.Identity.ListenerID,
			TotalAssignedJobs: pool.TotalAssignedJobs, MaxCapacity: actualCapacity, CapacityAcknowledged: capacityAcknowledged[target.ID],
			ZeroCapacityConfirmations: zeroConfirmations[target.ID],
			DrainServiceCapacity:      pool.DrainServiceCapacity,
			DesiredWorkers:            postPlan.DesiredWorkers[target.ID], UpdatedAt: now,
		})
	}
	problems := append([]model.Problem(nil), postPlan.Problems...)
	problems = append(problems, operationProblems...)
	var drainStartedAt *time.Time
	if postPlan.Phase == model.PhaseDraining {
		drainStartedAt = previous.DrainStartedAt
		if drainStartedAt == nil || now.Before(*drainStartedAt) {
			value := now
			drainStartedAt = &value
		}
		if now.Sub(*drainStartedAt) >= r.config.Drain.WarningAfter.Duration {
			problems = append(problems, problem(now, "drain-warning", "drain is taking longer than the configured warning threshold; active work will continue", "", false))
		}
	}
	phase := postPlan.Phase
	if len(operationProblems) > 0 {
		phase = model.PhaseDegraded
	}
	observed := model.ObservedState{
		SchemaVersion: 1, Phase: phase, HeartbeatAt: r.deps.Clock.Now().UTC(), DrainStartedAt: drainStartedAt, Version: r.version,
		Pools: observedPools, Workers: append([]model.Worker(nil), workers...), Resources: resources,
		Power: power, Desktop: desktop, ResourceGate: postPlan.ResourceGate, PowerGate: postPlan.PowerGate,
		Problems: problems,
	}
	if saveErr := r.deps.State.SaveObserved(ctx, observed); saveErr != nil {
		operationErrors = append(operationErrors, fmt.Errorf("save observed state: %w", saveErr))
	}
	return ReconcileResult{Observed: observed, Plan: postPlan}, errors.Join(operationErrors...)
}

func (r *Reconciler) ensure(ctx context.Context, target config.Target, previous *scaleset.Identity) (scaleset.Identity, error) {
	definition := scaleset.Definition{
		TargetID: target.ID, URL: target.URL, Scope: string(target.Scope), ClientID: target.ClientID, InstallationID: target.InstallationID, SecretID: target.SecretID,
		RunnerGroup: target.RunnerGroup, ScaleSetName: target.ScaleSetName, Labels: append([]string(nil), target.Labels...),
	}
	return RetryValue(ctx, r.deps.Clock, r.backoffPolicy(), scaleset.Retryable, func(callCtx context.Context) (scaleset.Identity, error) {
		return r.deps.ScaleSets.Ensure(callCtx, definition, previous)
	})
}

func (r *Reconciler) statistics(ctx context.Context, target config.Target, identity scaleset.Identity, maxCapacity int) (scaleset.Statistics, scaleset.Identity, error) {
	stats, err := RetryValue(ctx, r.deps.Clock, r.backoffPolicy(), scaleset.Retryable, func(callCtx context.Context) (scaleset.Statistics, error) {
		return r.deps.ScaleSets.Statistics(callCtx, identity, maxCapacity)
	})
	if err == nil {
		return stats, identity, nil
	}
	if !scaleset.IsKind(err, scaleset.ErrorNotFound) {
		return scaleset.Statistics{}, identity, err
	}
	// The persisted scale set was deleted externally. Recreate this host's own
	// identity, then retry the statistics call once through normal backoff.
	recreated, ensureErr := r.ensure(ctx, target, nil)
	if ensureErr != nil {
		return scaleset.Statistics{}, identity, errors.Join(err, ensureErr)
	}
	stats, statsErr := RetryValue(ctx, r.deps.Clock, r.backoffPolicy(), scaleset.Retryable, func(callCtx context.Context) (scaleset.Statistics, error) {
		return r.deps.ScaleSets.Statistics(callCtx, recreated, maxCapacity)
	})
	return stats, recreated, statsErr
}

func (r *Reconciler) deregisterRunner(ctx context.Context, poolID string, runnerID int64) error {
	if poolID == "" || runnerID <= 0 {
		return errors.New("positive GitHub runner ID and pool ID are required for deregistration")
	}
	_, err := RetryValue(ctx, r.deps.Clock, r.backoffPolicy(), scaleset.Retryable, func(callContext context.Context) (struct{}, error) {
		err := r.deps.ScaleSets.RemoveRunner(callContext, poolID, runnerID)
		if scaleset.IsKind(err, scaleset.ErrorNotFound) {
			err = nil
		}
		return struct{}{}, err
	})
	return err
}

func (r *Reconciler) target(id string) config.Target {
	for _, target := range r.config.GitHub.Targets {
		if target.ID == id {
			return target
		}
	}
	return config.Target{ID: id}
}

func (r *Reconciler) nextRunnerName(_ string, now time.Time) string {
	r.stateMu.Lock()
	r.sequence++
	sequence := r.sequence
	r.stateMu.Unlock()
	suffix := "-" + strconv.FormatInt(now.UnixNano(), 36) + "-" + strconv.FormatUint(sequence, 36)
	base := r.config.Host.RunnerNamePrefix
	const maximum = 64
	if len(base)+len(suffix) > maximum {
		base = strings.TrimRight(base[:maximum-len(suffix)], "-._")
	}
	return base + suffix
}

func (r *Reconciler) backoffPolicy() BackoffPolicy {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	return r.backoff
}

func (r *Reconciler) safetyWatchInterval() time.Duration {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	return r.watchInterval
}

func (r *Reconciler) rememberedDrainCapacity(poolID string) int {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	return r.drainCapacity[poolID]
}

func (r *Reconciler) rememberDrainCapacity(poolID string, capacity int) {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if capacity <= 0 {
		delete(r.drainCapacity, poolID)
		return
	}
	r.drainCapacity[poolID] = capacity
}

func (r *Reconciler) watchSafetyInputs(ctx context.Context, desired model.DesiredState, power model.PowerSnapshot, cancel context.CancelCauseFunc, forcedZero bool) {
	ticker := time.NewTicker(r.safetyWatchInterval())
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if !forcedZero {
				latestDesired, err := r.deps.State.LoadDesired(ctx)
				if errors.Is(err, statepkg.ErrNotFound) {
					latestDesired = model.DesiredState{SchemaVersion: 1, Mode: model.ModeDisabled}
					err = nil
				}
				if err != nil || !sameAdmissionIntent(desired, latestDesired) {
					cancel(errReconcileInputsChanged)
					return
				}
			}
			if !forcedZero && r.config.Power.Policy == config.PowerACOnly {
				latestPower, err := r.deps.Power.Snapshot(ctx)
				if err != nil || latestPower.ACConnected != power.ACConnected {
					cancel(errReconcileInputsChanged)
					return
				}
			}
		}
	}
}

func (r *Reconciler) freshStartAllowed(
	ctx context.Context,
	poolID string,
	pools []PoolSnapshot,
	previous model.ObservedState,
	baselineDesired model.DesiredState,
	baselinePower model.PowerSnapshot,
	baselineResources model.ResourceSnapshot,
	baselineDesktop model.DesktopStatus,
	reservedStarts int,
) (allowed bool, safetyChanged bool, err error) {
	desired, err := r.deps.State.LoadDesired(ctx)
	if errors.Is(err, statepkg.ErrNotFound) {
		desired = model.DesiredState{SchemaVersion: 1, Mode: model.ModeDisabled}
		err = nil
	}
	if err != nil {
		return false, true, err
	}
	if r.isShuttingDown() {
		desired.Mode = model.ModeDisabled
		desired.TemporaryCapacityOverride = nil
	}
	if !sameAdmissionIntent(baselineDesired, desired) {
		return false, true, nil
	}

	power, err := r.deps.Power.Snapshot(ctx)
	if err != nil {
		return false, true, err
	}
	if r.config.Power.Policy == config.PowerACOnly && power.ACConnected != baselinePower.ACConnected {
		return false, true, nil
	}
	resources, err := r.deps.Resources.Snapshot(ctx)
	if err != nil {
		return false, true, err
	}
	desktop, err := r.deps.Desktop.Status(ctx)
	if err != nil {
		return false, true, err
	}
	workers, err := r.deps.Workers.List(ctx)
	if err != nil {
		return false, true, err
	}
	enriched, lookupErr := r.enrichWorkerJobs(ctx, workers)
	if lookupErr != nil {
		return false, true, lookupErr
	}
	workers = enriched

	// A host monitor may not reflect the full envelope of a container that was
	// just started. Reserve that envelope explicitly for the rest of this Step;
	// this is what prevents a single stale snapshot from admitting N workers.
	workerMemory := uint64(r.config.Resources.Worker.Memory)
	var reservation uint64
	if workerMemory > 0 && uint64(reservedStarts) > ^uint64(0)/workerMemory {
		reservation = ^uint64(0)
	} else {
		reservation = uint64(reservedStarts) * workerMemory
	}
	if reservation >= resources.AvailableMemoryBytes {
		resources.AvailableMemoryBytes = 0
	} else {
		resources.AvailableMemoryBytes -= reservation
	}

	now := r.deps.Clock.Now().UTC()
	plan := BuildPlan(PlanInput{
		Config: r.config, Desired: desired, Previous: previous, Pools: pools,
		Workers: workers, Resources: resources, Power: power, Desktop: desktop, Now: now,
	})
	for _, decision := range plan.Start {
		if decision.PoolID == poolID && decision.Count > 0 {
			return true, false, nil
		}
	}
	changed := resources != baselineResources || desktop != baselineDesktop
	return false, changed && reservedStarts == 0, nil
}

func sameAdmissionIntent(left, right model.DesiredState) bool {
	if left.SchemaVersion != right.SchemaVersion || left.Mode != right.Mode {
		return false
	}
	if left.TemporaryCapacityOverride == nil || right.TemporaryCapacityOverride == nil {
		return left.TemporaryCapacityOverride == nil && right.TemporaryCapacityOverride == nil
	}
	return *left.TemporaryCapacityOverride == *right.TemporaryCapacityOverride
}

func safeScaleSetMessage(operation string, err error) string {
	var typed *scaleset.Error
	if errors.As(err, &typed) {
		if typed.StatusCode > 0 {
			return fmt.Sprintf("scale-set %s failed (%s, HTTP %d)", operation, typed.Kind, typed.StatusCode)
		}
		return fmt.Sprintf("scale-set %s failed (%s)", operation, typed.Kind)
	}
	return fmt.Sprintf("scale-set %s failed", operation)
}

func findPool(pools []PoolSnapshot, id string) PoolSnapshot {
	for _, pool := range pools {
		if pool.TargetID == id {
			return pool
		}
	}
	return PoolSnapshot{TargetID: id}
}

func containsActiveWorker(workers []model.Worker) bool {
	for _, worker := range workers {
		if worker.Active() {
			return true
		}
	}
	return false
}

func allTargetsStablyZero(targets []config.Target, acknowledged map[string]bool, confirmations map[string]int) bool {
	for _, target := range targets {
		if !acknowledged[target.ID] || confirmations[target.ID] < 2 {
			return false
		}
	}
	return true
}

// mayHaveManagedWorkers distinguishes the authoritative Desktop-stopped state
// from an ambiguous engine failure. When both Desktop and its engine are known
// stopped, no managed container can be active and querying Docker is expected
// to fail. Every unknown or contradictory state still requires inventory and
// therefore fails closed if the runtime cannot provide it.
func mayHaveManagedWorkers(desktop model.DesktopStatus, statusKnown bool) bool {
	return !statusKnown || desktop.DesktopRunning || desktop.EngineReachable
}

func (r *Reconciler) enrichWorkerJobs(ctx context.Context, workers []model.Worker) ([]model.Worker, error) {
	result := append([]model.Worker(nil), workers...)
	for index := range result {
		jobID, found, err := r.deps.Jobs.ActiveJob(ctx, result[index].PoolID, result[index].Name)
		if err != nil {
			return nil, err
		}
		if found {
			result[index].JobID = jobID
			result[index].State = model.WorkerBusy
		}
	}
	return result, nil
}
