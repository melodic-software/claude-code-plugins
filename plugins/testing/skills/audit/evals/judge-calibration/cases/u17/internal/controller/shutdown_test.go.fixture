package controller

import (
	"context"
	"sync"
	"testing"

	"github.com/melodic-software/ci-runner/internal/config"
	"github.com/melodic-software/ci-runner/internal/model"
	"github.com/melodic-software/ci-runner/internal/scaleset"
)

func TestShutdownDrainsTransientlyAndClosesAdapters(t *testing.T) {
	t.Parallel()
	harness := newHarness(t, model.ModeEnabled)
	harness.runtime.workers = []model.Worker{{ID: "idle", PoolID: "org", State: model.WorkerIdle}}
	scaleSets := &closingScaleSet{Client: harness.scaleSets}
	harness.controller.deps.ScaleSets = scaleSets
	if err := harness.controller.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !harness.controller.ShuttingDown() {
		t.Fatal("shutdown flag was not retained")
	}
	if !scaleSets.isClosed() || !harness.runtime.closedValue() {
		t.Fatalf("adapters closed: scaleset=%v runtime=%v", scaleSets.isClosed(), harness.runtime.closedValue())
	}
	for _, call := range harness.scaleSets.SnapshotCalls() {
		if call.Operation == "statistics" && call.MaxCapacity != 0 {
			t.Fatalf("shutdown poll advertised capacity %d", call.MaxCapacity)
		}
	}
	desired, err := harness.store.LoadDesired(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if desired.Mode != model.ModeEnabled {
		t.Fatalf("shutdown persisted transient mode over user intent: %s", desired.Mode)
	}
}

func TestShutdownDrainedRequiresZeroCapacityAndNoActiveWorker(t *testing.T) {
	t.Parallel()
	targets := []config.Target{{ID: "org"}}
	if shutdownDrained(model.ObservedState{Pools: []model.PoolObservation{{ID: "org", MaxCapacity: 1, CapacityAcknowledged: true}}}, targets) {
		t.Fatal("nonzero listener capacity considered drained")
	}
	if shutdownDrained(model.ObservedState{Pools: []model.PoolObservation{{ID: "org", CapacityAcknowledged: true}}, Workers: []model.Worker{{State: model.WorkerBusy}}}, targets) {
		t.Fatal("busy worker considered drained")
	}
	if shutdownDrained(model.ObservedState{Pools: []model.PoolObservation{{ID: "org", CapacityAcknowledged: true, TotalAssignedJobs: 1}}}, targets) {
		t.Fatal("assigned work considered drained")
	}
	if shutdownDrained(model.ObservedState{}, targets) {
		t.Fatal("missing pool observation considered drained")
	}
	if !shutdownDrained(model.ObservedState{Pools: []model.PoolObservation{{ID: "org", CapacityAcknowledged: true, ZeroCapacityConfirmations: 2}}}, targets) {
		t.Fatal("zero-capacity empty fleet was not drained")
	}
}

type closingScaleSet struct {
	scaleset.Client
	mu     sync.Mutex
	closed bool
}

func (c *closingScaleSet) Close(context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.closed = true
	return nil
}
func (c *closingScaleSet) isClosed() bool { c.mu.Lock(); defer c.mu.Unlock(); return c.closed }
