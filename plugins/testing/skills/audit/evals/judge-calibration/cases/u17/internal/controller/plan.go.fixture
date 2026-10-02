// Package controller contains the platform-neutral reconciliation policy.
package controller

import (
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/melodic-software/ci-runner/internal/config"
	"github.com/melodic-software/ci-runner/internal/model"
	"github.com/melodic-software/ci-runner/internal/scaleset"
)

type PoolSnapshot struct {
	TargetID             string
	Identity             scaleset.Identity
	TotalAssignedJobs    int
	DrainServiceCapacity int
	Ready                bool
}

type PlanInput struct {
	Config    config.Config
	Desired   model.DesiredState
	Previous  model.ObservedState
	Pools     []PoolSnapshot
	Workers   []model.Worker
	Resources model.ResourceSnapshot
	Power     model.PowerSnapshot
	Desktop   model.DesktopStatus
	Now       time.Time
}

type StartDecision struct {
	PoolID string
	Count  int
}

type Plan struct {
	Phase              model.Phase
	AdvertisedCapacity map[string]int
	DesiredWorkers     map[string]int
	Start              []StartDecision
	Remove             []model.Worker
	StartDesktop       bool
	StopDesktop        bool
	ShutdownWSL        bool
	ResourceGate       model.ResourceGateState
	PowerGate          model.PowerGateState
	Problems           []model.Problem
}

// BuildPlan is pure: it computes a complete desired transition without
// invoking an adapter. Lower target priority values are allocated first.
func BuildPlan(input PlanInput) Plan {
	plan := Plan{
		Phase:              model.PhaseStarting,
		AdvertisedCapacity: make(map[string]int, len(input.Config.GitHub.Targets)),
		DesiredWorkers:     make(map[string]int, len(input.Config.GitHub.Targets)),
	}
	for _, target := range input.Config.GitHub.Targets {
		plan.AdvertisedCapacity[target.ID] = 0
		plan.DesiredWorkers[target.ID] = 0
	}
	if input.Now.IsZero() {
		input.Now = time.Now().UTC()
	}

	var resourceHealthy bool
	var resourceProblem string
	plan.ResourceGate, resourceHealthy, resourceProblem = evaluateResourceGate(
		input.Previous.ResourceGate,
		input.Resources,
		input.Config.Resources,
		input.Now,
	)
	if resourceProblem != "" {
		plan.Problems = append(plan.Problems, problem(input.Now, "invalid-resource-observation", resourceProblem, "", true))
	}
	var powerAllowed bool
	plan.PowerGate, powerAllowed = evaluatePowerGate(
		input.Previous.PowerGate,
		input.Power,
		input.Config.Power,
		input.Now,
	)

	workersByPool := make(map[string][]model.Worker, len(input.Config.GitHub.Targets))
	targetIDs := make(map[string]struct{}, len(input.Config.GitHub.Targets))
	busyWorkers := 0
	activeWorkers := 0
	for _, target := range input.Config.GitHub.Targets {
		targetIDs[target.ID] = struct{}{}
	}
	for _, worker := range input.Workers {
		workersByPool[worker.PoolID] = append(workersByPool[worker.PoolID], worker)
		if worker.State == model.WorkerBusy {
			busyWorkers++
		}
		if worker.Active() {
			activeWorkers++
		}
		if _, known := targetIDs[worker.PoolID]; !known {
			switch worker.State {
			case model.WorkerExited:
				plan.Remove = append(plan.Remove, worker)
			case model.WorkerBusy:
				plan.Problems = append(plan.Problems, problem(input.Now, "orphaned-busy-worker", "busy worker belongs to an unknown pool and will be preserved", worker.PoolID, false))
			default:
				plan.Problems = append(plan.Problems, problem(input.Now, "orphaned-worker-retirement-deferred", "active worker belongs to an unknown pool and cannot be quiesced safely; it will be preserved", worker.PoolID, false))
			}
		}
	}
	if !input.Desired.Mode.Valid() {
		plan.Phase = model.PhaseDegraded
		plan.Problems = append(plan.Problems, problem(input.Now, "invalid-desired-mode", fmt.Sprintf("unsupported desired mode %q", input.Desired.Mode), "", false))
		applyOutstandingAssignments(&plan, input, workersByPool, targetIDs, activeWorkers)
		return plan
	}

	switch input.Desired.Mode {
	case model.ModeDisabled:
		outstanding := applyOutstandingAssignments(&plan, input, workersByPool, targetIDs, activeWorkers)
		if hasActiveWorkers(input.Workers) || outstanding || len(plan.Start) > 0 {
			plan.Phase = model.PhaseDraining
		} else {
			plan.Phase = model.PhaseDisabled
		}
		return plan

	case model.ModeGaming:
		outstanding := applyOutstandingAssignments(&plan, input, workersByPool, targetIDs, activeWorkers)
		if busyWorkers > 0 || outstanding || len(plan.Start) > 0 {
			plan.Phase = model.PhaseDraining
			return plan
		}
		plan.StopDesktop = input.Desktop.DesktopRunning || input.Desktop.EngineReachable
		plan.ShutdownWSL = input.Desktop.RunningWSLCount > 0
		if plan.StopDesktop || plan.ShutdownWSL || hasActiveWorkers(input.Workers) {
			plan.Phase = model.PhaseDraining
		} else {
			plan.Phase = model.PhaseGaming
		}
		return plan
	}

	if !powerAllowed {
		applyOutstandingAssignments(&plan, input, workersByPool, targetIDs, activeWorkers)
		plan.Phase = model.PhasePowerSuspended
		return plan
	}
	if !resourceHealthy {
		applyOutstandingAssignments(&plan, input, workersByPool, targetIDs, activeWorkers)
		plan.Phase = model.PhaseResourceConstrained
		return plan
	}
	if !input.Desktop.DesktopRunning || !input.Desktop.EngineReachable {
		plan.StartDesktop = true
		plan.Phase = model.PhaseStarting
		return plan
	}

	poolByID := make(map[string]PoolSnapshot, len(input.Pools))
	for _, pool := range input.Pools {
		poolByID[pool.TargetID] = pool
	}
	targets := append([]config.Target(nil), input.Config.GitHub.Targets...)
	sort.SliceStable(targets, func(i, j int) bool {
		if targets[i].Priority == targets[j].Priority {
			return targets[i].ID < targets[j].ID
		}
		return targets[i].Priority < targets[j].Priority
	})

	hostLimit := input.Config.Resources.MaximumConcurrentWorkers
	if input.Desired.TemporaryCapacityOverride != nil {
		hostLimit = *input.Desired.TemporaryCapacityOverride
	}
	if hostLimit < 0 {
		plan.Phase = model.PhaseDegraded
		plan.Problems = append(plan.Problems, problem(input.Now, "invalid-capacity-override", "temporary capacity override must not be negative", "", false))
		appendSafeRemovals(&plan, workersByPool, targetIDs, nil)
		return plan
	}

	// Derive how many additional full worker envelopes can fit while preserving
	// the configured physical-memory floor. This bounds a multi-worker plan; a
	// one-worker boolean gate would otherwise admit several containers from the
	// same stale snapshot.
	resourceLimit := activeWorkers + availableWorkerSlots(input.Resources, input.Config.Resources)
	if resourceLimit < hostLimit {
		hostLimit = resourceLimit
	}

	// Busy workers are immutable reservations. They consume global capacity
	// before any target receives assigned-job or warm-idle capacity.
	remaining := hostLimit - busyWorkers
	if remaining < 0 {
		remaining = 0
		plan.Problems = append(plan.Problems, problem(input.Now, "capacity-below-busy-count", "configured host capacity is below the current busy-worker count; active work is preserved and no new work is admitted", "", false))
	}
	for _, target := range targets {
		for _, worker := range workersByPool[target.ID] {
			if worker.State == model.WorkerBusy {
				plan.DesiredWorkers[target.ID]++
			}
		}
	}

	for _, target := range targets {
		pool, exists := poolByID[target.ID]
		if !exists || !pool.Ready {
			plan.Problems = append(plan.Problems, problem(input.Now, "pool-unavailable", "scale-set listener is unavailable; capacity is held at zero", target.ID, true))
			continue
		}
		assigned := pool.TotalAssignedJobs
		if assigned < 0 {
			assigned = 0
			plan.Problems = append(plan.Problems, problem(input.Now, "invalid-assigned-job-count", "GitHub reported a negative TotalAssignedJobs value", target.ID, true))
		}
		rawDesired := minInt(target.MaxCapacity, assigned+target.WarmIdle)
		busy := plan.DesiredWorkers[target.ID]
		if rawDesired < busy {
			rawDesired = busy
		}
		need := rawDesired - busy
		granted := minInt(need, remaining)
		plan.DesiredWorkers[target.ID] = busy + granted
		remaining -= granted
	}

	capacityDebt := busyWorkers > hostLimit
	quiescing := false
	for _, target := range targets {
		desired := plan.DesiredWorkers[target.ID]
		active := 0
		removable := make([]model.Worker, 0)
		for _, worker := range workersByPool[target.ID] {
			switch worker.State {
			case model.WorkerBusy:
				active++
			case model.WorkerStarting, model.WorkerIdle:
				active++
				removable = append(removable, worker)
			case model.WorkerExited:
				plan.Remove = append(plan.Remove, worker)
			}
		}
		if active < desired {
			plan.Start = append(plan.Start, StartDecision{PoolID: target.ID, Count: desired - active})
		}
		// An enabled pool must quiesce before it shrinks. Capacity remains zero
		// while active exceeds desired; Reconciler requires two authoritative
		// zero-assignment polls plus durable no-active-job evidence before any
		// selected worker is deregistered and removed. The next cycle restores
		// desired capacity after inventory proves the excess is gone.
		if active > desired {
			quiescing = true
			excess := active - desired
			for _, worker := range removable {
				if excess == 0 {
					break
				}
				plan.Remove = append(plan.Remove, worker)
				excess--
			}
		} else if !capacityDebt {
			plan.AdvertisedCapacity[target.ID] = desired
		}
	}
	if len(plan.Problems) > 0 {
		plan.Phase = model.PhaseDegraded
	} else if quiescing {
		plan.Phase = model.PhaseDraining
	} else {
		plan.Phase = model.PhaseReady
	}
	return plan
}

// applyOutstandingAssignments closes the gap between the official client
// acquiring a job and the worker hook reporting "busy". Capacity remains zero,
// but existing nonbusy workers are retained and missing one-job workers are
// started up to the last nonzero acknowledged capacity that could have caused
// the assignment.
func applyOutstandingAssignments(plan *Plan, input PlanInput, workersByPool map[string][]model.Worker, known map[string]struct{}, activeWorkers int) bool {
	poolByID := make(map[string]PoolSnapshot, len(input.Pools))
	reservations := make(map[string]int, len(input.Pools))
	outstanding := false
	for _, pool := range input.Pools {
		poolByID[pool.TargetID] = pool
		if _, ok := known[pool.TargetID]; !ok || !pool.Ready || pool.TotalAssignedJobs <= 0 {
			continue
		}
		busy := 0
		for _, worker := range workersByPool[pool.TargetID] {
			if worker.State == model.WorkerBusy {
				busy++
			}
		}
		if uncovered := pool.TotalAssignedJobs - busy; uncovered > 0 {
			reservations[pool.TargetID] = uncovered
			outstanding = true
		}
	}
	appendSafeRemovals(plan, workersByPool, known, reservations)

	remaining := input.Config.Resources.MaximumConcurrentWorkers - activeWorkers
	if remaining < 0 {
		remaining = 0
	}
	targets := append([]config.Target(nil), input.Config.GitHub.Targets...)
	sort.SliceStable(targets, func(i, j int) bool {
		if targets[i].Priority == targets[j].Priority {
			return targets[i].ID < targets[j].ID
		}
		return targets[i].Priority < targets[j].Priority
	})
	for _, target := range targets {
		pool := poolByID[target.ID]
		uncovered := reservations[target.ID]
		busy, nonbusy := 0, 0
		for _, worker := range workersByPool[target.ID] {
			switch worker.State {
			case model.WorkerBusy:
				busy++
			case model.WorkerStarting, model.WorkerIdle:
				nonbusy++
			}
		}
		serviceable := minInt(uncovered, minInt(pool.DrainServiceCapacity, target.MaxCapacity))
		start := minInt(maxInt(0, serviceable-nonbusy), remaining)
		if start > 0 {
			plan.Start = append(plan.Start, StartDecision{PoolID: target.ID, Count: start})
			remaining -= start
			if !input.Desktop.DesktopRunning || !input.Desktop.EngineReachable {
				plan.StartDesktop = true
			}
		}
		plan.DesiredWorkers[target.ID] = busy + minInt(uncovered, nonbusy+start)
		if uncovered > nonbusy+start {
			plan.Problems = append(plan.Problems, problem(input.Now, "assigned-job-capacity-unavailable", "GitHub has assigned work that exceeds the last acknowledged service capacity; capacity remains zero and existing workers are preserved", target.ID, true))
		}
	}
	return outstanding
}

func appendSafeRemovals(plan *Plan, workersByPool map[string][]model.Worker, known map[string]struct{}, desired map[string]int) {
	for poolID, workers := range workersByPool {
		if _, ok := known[poolID]; !ok {
			continue // unknown nonbusy workers were already appended exactly once
		}
		keep := 0
		if desired != nil {
			keep = desired[poolID]
		}
		activeNonBusy := 0
		for _, worker := range workers {
			if worker.State == model.WorkerStarting || worker.State == model.WorkerIdle {
				activeNonBusy++
			}
		}
		removeCount := activeNonBusy - keep
		for _, worker := range workers {
			if worker.State == model.WorkerExited {
				plan.Remove = append(plan.Remove, worker)
				continue
			}
			if removeCount > 0 && (worker.State == model.WorkerStarting || worker.State == model.WorkerIdle) {
				plan.Remove = append(plan.Remove, worker)
				removeCount--
			}
		}
	}
}

func hasActiveWorkers(workers []model.Worker) bool {
	for _, worker := range workers {
		if worker.Active() {
			return true
		}
	}
	return false
}

func evaluateResourceGate(previous model.ResourceGateState, snapshot model.ResourceSnapshot, policy config.Resources, now time.Time) (model.ResourceGateState, bool, string) {
	state := previous
	if snapshot.TotalMemoryBytes == 0 || snapshot.AvailableMemoryBytes > snapshot.TotalMemoryBytes || math.IsNaN(snapshot.CPUUtilizationPercent) || math.IsInf(snapshot.CPUUtilizationPercent, 0) || snapshot.CPUUtilizationPercent < 0 || snapshot.CPUUtilizationPercent > 100 {
		state.Blocked = true
		state.HighCPUSince = nil
		state.HealthySince = nil
		return state, false, "resource monitor returned an out-of-range CPU or physical-memory observation"
	}
	memoryHealthy := availableWorkerSlots(snapshot, policy) > 0

	if !state.Blocked {
		state.HealthySince = nil
		if !memoryHealthy {
			state.Blocked = true
			state.HighCPUSince = nil
			return state, false, ""
		}
		if snapshot.CPUUtilizationPercent >= policy.CPUBlockPercent {
			if state.HighCPUSince == nil || now.Before(*state.HighCPUSince) {
				value := now
				state.HighCPUSince = &value
			}
			if now.Sub(*state.HighCPUSince) >= policy.CPUObservationWindow.Duration {
				state.Blocked = true
				state.HealthySince = nil
				return state, false, ""
			}
		} else {
			state.HighCPUSince = nil
		}
		return state, true, ""
	}

	state.HighCPUSince = nil
	if memoryHealthy && snapshot.CPUUtilizationPercent <= policy.CPUResumePercent {
		if state.HealthySince == nil || now.Before(*state.HealthySince) {
			value := now
			state.HealthySince = &value
		}
		if now.Sub(*state.HealthySince) >= policy.CPUHysteresisWindow.Duration {
			state.Blocked = false
			state.HealthySince = nil
			return state, true, ""
		}
	} else {
		state.HealthySince = nil
	}
	return state, false, ""
}

func availableWorkerSlots(snapshot model.ResourceSnapshot, policy config.Resources) int {
	workerMemory := uint64(policy.Worker.Memory)
	if snapshot.TotalMemoryBytes == 0 || workerMemory == 0 || snapshot.AvailableMemoryBytes > snapshot.TotalMemoryBytes {
		return 0
	}
	reserved := uint64(math.Ceil(float64(snapshot.TotalMemoryBytes) * policy.MinimumAvailableMemoryPct / 100))
	if snapshot.AvailableMemoryBytes <= reserved {
		return 0
	}
	slots := (snapshot.AvailableMemoryBytes - reserved) / workerMemory
	maxInt := uint64(^uint(0) >> 1)
	if slots > maxInt {
		return int(maxInt)
	}
	return int(slots)
}

func evaluatePowerGate(previous model.PowerGateState, snapshot model.PowerSnapshot, policy config.Power, now time.Time) (model.PowerGateState, bool) {
	if policy.Policy == config.PowerAlways {
		return model.PowerGateState{}, true
	}
	state := previous
	if !snapshot.ACConnected {
		state.ACSince = nil
		return state, false
	}
	if state.ACSince == nil || now.Before(*state.ACSince) {
		value := now
		state.ACSince = &value
		return state, false
	}
	return state, now.Sub(*state.ACSince) >= policy.StableACWindow.Duration
}

func problem(now time.Time, code, message, poolID string, retryable bool) model.Problem {
	return model.Problem{Code: code, Message: message, PoolID: poolID, Retryable: retryable, At: now}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
