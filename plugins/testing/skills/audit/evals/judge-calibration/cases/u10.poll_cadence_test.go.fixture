package controller

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/melodic-software/ci-runner/internal/config"
	"github.com/melodic-software/ci-runner/internal/model"
	"github.com/melodic-software/ci-runner/internal/scaleset"
)

func TestResourceRecoveryInterruptsLongPollAtReconcileCadence(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	now := harness.clock.Now()
	if err := harness.store.SaveObserved(context.Background(), model.ObservedState{
		SchemaVersion: 1, Phase: model.PhaseResourceConstrained, HeartbeatAt: now.Add(-time.Minute),
		Pools:        []model.PoolObservation{{ID: "org", ScaleSetID: 1, ListenerID: "listener-org", MaxCapacity: 0, CapacityAcknowledged: true}},
		ResourceGate: model.ResourceGateState{Blocked: true, Reason: model.ResourceGateReasonCPU},
	}); err != nil {
		t.Fatal(err)
	}
	blocking := newFirstBlockingScaleSet(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	done := make(chan ReconcileResult, 1)
	go func() {
		result, _ := harness.controller.Step(context.Background())
		done <- result
	}()
	waitForSignal(t, blocking.entered, "zero-capacity listener poll did not begin")

	checkpoint, err := harness.store.LoadObserved(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if checkpoint.ResourceGate.HealthySince == nil || !checkpoint.ResourceGate.HealthySince.Equal(now) {
		t.Fatalf("healthy recovery start was not checkpointed before the long poll: %#v", checkpoint.ResourceGate)
	}
	harness.clock.Advance(harness.controller.config.Resources.CPUHysteresisWindow.Duration)

	select {
	case result := <-done:
		if result.Observed.Phase != model.PhaseReady || result.Observed.ResourceGate.Blocked {
			t.Fatalf("resource gate did not recover: %#v", result.Observed)
		}
	case <-time.After(time.Second):
		t.Fatal("resource recovery remained trapped behind the listener long poll")
	}
	if got := blocking.capacitiesSnapshot(); fmt.Sprint(got) != "[0 3]" {
		t.Fatalf("advertised capacities = %v, want [0 3]", got)
	}
}

func TestPowerRecoveryInterruptsLongPollAtReconcileCadence(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	harness.controller.config.Power.Policy = config.PowerACOnly
	now := harness.clock.Now()
	acSince := now
	if err := harness.store.SaveObserved(context.Background(), model.ObservedState{
		SchemaVersion: 1, Phase: model.PhasePowerSuspended, HeartbeatAt: now.Add(-time.Minute),
		Pools:     []model.PoolObservation{{ID: "org", ScaleSetID: 1, ListenerID: "listener-org", MaxCapacity: 0, CapacityAcknowledged: true}},
		PowerGate: model.PowerGateState{ACSince: &acSince},
	}); err != nil {
		t.Fatal(err)
	}
	harness.controller.deps.Power = &mutablePower{snapshot: model.PowerSnapshot{ACConnected: true, ObservedAt: now}}
	blocking := newFirstBlockingScaleSet(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	done := make(chan ReconcileResult, 1)
	go func() {
		result, _ := harness.controller.Step(context.Background())
		done <- result
	}()
	waitForSignal(t, blocking.entered, "power-suspended listener poll did not begin")
	harness.clock.Advance(harness.controller.config.Power.StableACWindow.Duration)

	select {
	case result := <-done:
		if result.Observed.Phase != model.PhaseReady {
			t.Fatalf("power gate did not recover: %#v", result.Observed)
		}
	case <-time.After(time.Second):
		t.Fatal("stable-AC recovery remained trapped behind the listener long poll")
	}
	if got := blocking.capacitiesSnapshot(); fmt.Sprint(got) != "[0 3]" {
		t.Fatalf("advertised capacities = %v, want [0 3]", got)
	}
}

func TestInvalidResourceObservationCancelsNonzeroPollAndPreservesRacingAssignment(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	now := harness.clock.Now()
	if err := harness.store.SaveObserved(context.Background(), model.ObservedState{
		SchemaVersion: 1, Phase: model.PhaseReady, HeartbeatAt: now,
		Pools: []model.PoolObservation{{ID: "org", ScaleSetID: 1, ListenerID: "listener-org", MaxCapacity: 3, CapacityAcknowledged: true}},
	}); err != nil {
		t.Fatal(err)
	}
	resources := &mutableResources{snapshot: model.ResourceSnapshot{TotalMemoryBytes: 64 << 30, AvailableMemoryBytes: 64 << 30, CPUUtilizationPercent: 10}}
	harness.controller.deps.Resources = resources
	blocking := newAssignmentOnCancelScaleSet(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	done := make(chan ReconcileResult, 1)
	go func() {
		result, _ := harness.controller.Step(context.Background())
		done <- result
	}()
	waitForSignal(t, blocking.entered, "nonzero listener poll did not begin")
	resources.set(model.ResourceSnapshot{})

	select {
	case result := <-done:
		if !result.Observed.ResourceGate.Blocked || result.Observed.ResourceGate.Reason != model.ResourceGateReasonInvalidObservation {
			t.Fatalf("invalid resource observation did not fail closed: %#v", result.Observed)
		}
		if harness.runtime.startCount() != 1 || len(result.Observed.Workers) != 1 {
			t.Fatalf("assignment that won the cancellation race was not serviced exactly once: starts=%d workers=%#v", harness.runtime.startCount(), result.Observed.Workers)
		}
	case <-time.After(time.Second):
		t.Fatal("invalid resource observation did not cancel nonzero listener capacity")
	}
	if got := blocking.capacitiesSnapshot(); fmt.Sprint(got) != "[3 0]" {
		t.Fatalf("advertised capacities = %v, want [3 0]", got)
	}
}

func TestHeartbeatCheckpointDoesNotRestartStableLongPoll(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	now := harness.clock.Now()
	if err := harness.store.SaveObserved(context.Background(), model.ObservedState{
		SchemaVersion: 1, Phase: model.PhaseReady, HeartbeatAt: now.Add(-time.Minute),
		Pools: []model.PoolObservation{{ID: "org", ScaleSetID: 1, ListenerID: "listener-org", MaxCapacity: 3, CapacityAcknowledged: true}},
	}); err != nil {
		t.Fatal(err)
	}
	harness.runtime.workers = []model.Worker{{ID: "idle", Name: "idle", PoolID: "org", RunnerID: 1000, State: model.WorkerIdle}}
	notifying := &notifyingStateStore{StateStore: harness.store, saved: make(chan model.ObservedState, 8)}
	harness.controller.deps.State = notifying
	blocking := newFirstBlockingScaleSet(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		_, err := harness.controller.Step(ctx)
		done <- err
	}()
	waitForSignal(t, blocking.entered, "stable listener poll did not begin")
	for len(notifying.saved) > 0 {
		<-notifying.saved
	}
	harness.clock.Advance(harness.controller.config.Controller.ReconcileInterval.Duration)

	checkpoint := waitForObserved(t, notifying.saved, func(observed model.ObservedState) bool {
		return observed.HeartbeatAt.Equal(harness.clock.Now())
	}, "heartbeat was not checkpointed on the reconcile cadence")
	if len(checkpoint.Pools) != 1 || !checkpoint.Pools[0].CapacityAcknowledged || checkpoint.Pools[0].MaxCapacity != 3 {
		t.Fatalf("stable acknowledged capacity was corrupted by heartbeat checkpoint: %#v", checkpoint.Pools)
	}
	if got := blocking.capacitiesSnapshot(); fmt.Sprint(got) != "[3]" {
		t.Fatalf("stable long poll was restarted: capacities=%v", got)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("canceled stable listener poll did not stop")
	}
}

func TestWorkerExitInterruptsLongPollAndStartsAssignedReplacements(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	harness.runtime.workers = []model.Worker{{
		ID: "completed", Name: "runner-completed", PoolID: "org", RunnerID: 1000, State: model.WorkerIdle,
	}}
	harness.scaleSets.Stats["statistics:1"] = scaleset.Statistics{TotalAssignedJobs: 1}
	blocking := newFirstBlockingScaleSet(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	done := make(chan ReconcileResult, 1)
	go func() {
		result, _ := harness.controller.Step(context.Background())
		done <- result
	}()
	waitForSignal(t, blocking.entered, "listener poll did not begin")

	harness.runtime.mu.Lock()
	harness.runtime.workers = nil
	harness.runtime.mu.Unlock()

	select {
	case result := <-done:
		if result.Observed.Pools[0].TotalAssignedJobs != 1 || result.Observed.Pools[0].DesiredWorkers != 2 {
			t.Fatalf("assigned replacement plan was not observed: %#v", result.Observed)
		}
		if harness.runtime.startCount() != 2 || len(result.Observed.Workers) != 2 {
			t.Fatalf("completed worker blocked replacement starts: starts=%d workers=%#v", harness.runtime.startCount(), result.Observed.Workers)
		}
	case <-time.After(time.Second):
		t.Fatal("completed worker remained stale behind the listener long poll")
	}
	if got := blocking.capacitiesSnapshot(); len(got) < 2 {
		t.Fatalf("worker exit did not restart listener poll: capacities=%v", got)
	}
}

func TestSameWorkerInventoryIgnoresOrderingButDetectsLifecycleChanges(t *testing.T) {
	t.Parallel()
	left := []model.Worker{
		{ID: "a", PoolID: "org", State: model.WorkerIdle},
		{ID: "b", PoolID: "org", State: model.WorkerIdle},
	}
	right := []model.Worker{left[1], left[0]}
	if !sameWorkerInventory(left, right) {
		t.Fatal("worker ordering was treated as an inventory change")
	}
	right[0].State = model.WorkerExited
	if sameWorkerInventory(left, right) {
		t.Fatal("worker lifecycle change was ignored")
	}
}

func TestPoolAcknowledgementTransitionTimestampDoesNotResetWhilePending(t *testing.T) {
	t.Parallel()
	started := time.Unix(100, 0).UTC()
	now := started.Add(30 * time.Second)
	prior := model.PoolObservation{
		ScaleSetID: 1, ListenerID: "listener", MaxCapacity: 8,
		CapacityAcknowledged: false, UpdatedAt: started,
	}
	if got := poolAcknowledgementTransitionAt(prior, 1, "listener", 8, false, now); !got.Equal(started) {
		t.Fatalf("pending transition timestamp reset to %s", got)
	}
	reconciler := &Reconciler{pendingCapacity: map[string]int{"org": 8}}
	if got := reconciler.poolAcknowledgementTransitionAt("org", prior, 1, "listener", 8, 8, false, now); !got.Equal(started) {
		t.Fatalf("same pending capacity reset transition timestamp to %s", got)
	}
	if got := reconciler.poolAcknowledgementTransitionAt("org", prior, 1, "listener", 8, 6, false, now); !got.Equal(now) {
		t.Fatalf("changed pending capacity retained stale transition timestamp %s", got)
	}
	if got := poolAcknowledgementTransitionAt(prior, 1, "listener", 6, false, now); !got.Equal(now) {
		t.Fatalf("capacity transition timestamp = %s, want %s", got, now)
	}
	if got := poolAcknowledgementTransitionAt(prior, 1, "listener", 8, true, now); !got.Equal(now) {
		t.Fatalf("acknowledgement transition timestamp = %s, want %s", got, now)
	}
}

func TestFailedLongPollPreservesCadenceAcknowledgementTransitionAge(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.controller.config.Controller.ReconcileInterval.Duration = 5 * time.Millisecond
	started := harness.clock.Now()
	if err := harness.store.SaveObserved(context.Background(), model.ObservedState{
		SchemaVersion: 1, Phase: model.PhaseReady, HeartbeatAt: started,
		Pools: []model.PoolObservation{{
			ID: "org", ScaleSetID: 1, ListenerID: "listener-org", MaxCapacity: 8,
			CapacityAcknowledged: true, UpdatedAt: started.Add(-time.Minute),
		}},
	}); err != nil {
		t.Fatal(err)
	}
	notifying := &notifyingStateStore{StateStore: harness.store, saved: make(chan model.ObservedState, 8)}
	harness.controller.deps.State = notifying
	blocking := newBlockingPollFailure(harness.scaleSets)
	harness.controller.deps.ScaleSets = blocking
	type outcome struct {
		result ReconcileResult
		err    error
	}
	done := make(chan outcome, 1)
	go func() {
		result, err := harness.controller.Step(context.Background())
		done <- outcome{result: result, err: err}
	}()
	waitForSignal(t, blocking.entered, "listener poll did not begin")
	checkpoint := waitForObserved(t, notifying.saved, func(observed model.ObservedState) bool {
		return len(observed.Pools) == 1 && !observed.Pools[0].CapacityAcknowledged
	}, "pending acknowledgement transition was not checkpointed")
	transitionAt := checkpoint.Pools[0].UpdatedAt
	if !transitionAt.Equal(started) {
		t.Fatalf("transition started at %s, want %s", transitionAt, started)
	}
	harness.clock.Advance(30 * time.Second)
	close(blocking.release)
	select {
	case got := <-done:
		if got.err == nil {
			t.Fatal("failed listener poll returned no error")
		}
		if len(got.result.Observed.Pools) != 1 || !got.result.Observed.Pools[0].UpdatedAt.Equal(transitionAt) {
			t.Fatalf("failed poll reset transition age: %#v", got.result.Observed.Pools)
		}
	case <-time.After(time.Second):
		t.Fatal("failed listener poll did not finish")
	}
}

type mutableResources struct {
	mu       sync.Mutex
	snapshot model.ResourceSnapshot
	err      error
}

type blockingPollFailure struct {
	scaleset.Client
	entered chan struct{}
	release chan struct{}
	once    sync.Once
}

func newBlockingPollFailure(client scaleset.Client) *blockingPollFailure {
	return &blockingPollFailure{Client: client, entered: make(chan struct{}), release: make(chan struct{})}
}

func (s *blockingPollFailure) Statistics(context.Context, scaleset.Identity, int) (scaleset.Statistics, error) {
	s.once.Do(func() { close(s.entered) })
	<-s.release
	return scaleset.Statistics{}, errors.New("listener poll failed")
}

func (m *mutableResources) Snapshot(context.Context) (model.ResourceSnapshot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.snapshot, m.err
}

func (m *mutableResources) set(snapshot model.ResourceSnapshot) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.snapshot = snapshot
}

type assignmentOnCancelScaleSet struct {
	scaleset.Client
	entered chan struct{}
	mu      sync.Mutex
	calls   int
	maxima  []int
}

func newAssignmentOnCancelScaleSet(client scaleset.Client) *assignmentOnCancelScaleSet {
	return &assignmentOnCancelScaleSet{Client: client, entered: make(chan struct{})}
}

func (s *assignmentOnCancelScaleSet) Statistics(ctx context.Context, _ scaleset.Identity, maximum int) (scaleset.Statistics, error) {
	s.mu.Lock()
	s.calls++
	call := s.calls
	s.maxima = append(s.maxima, maximum)
	if call == 1 {
		close(s.entered)
	}
	s.mu.Unlock()
	if call == 1 {
		<-ctx.Done()
	}
	return scaleset.Statistics{TotalAssignedJobs: 1}, nil
}

func (s *assignmentOnCancelScaleSet) capacitiesSnapshot() []int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]int(nil), s.maxima...)
}

type notifyingStateStore struct {
	StateStore
	saved chan model.ObservedState
}

func (s *notifyingStateStore) SaveObserved(ctx context.Context, observed model.ObservedState) error {
	if err := s.StateStore.SaveObserved(ctx, observed); err != nil {
		return err
	}
	select {
	case s.saved <- observed:
	default:
	}
	return nil
}

func waitForObserved(t *testing.T, saved <-chan model.ObservedState, predicate func(model.ObservedState) bool, message string) model.ObservedState {
	t.Helper()
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	for {
		select {
		case observed := <-saved:
			if predicate(observed) {
				return observed
			}
		case <-timer.C:
			t.Fatal(message)
		}
	}
}
