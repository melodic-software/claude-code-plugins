#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p cmd/ingest config db deploy docs/vendor .work/review-target/design

cat >go.mod <<'MOD'
module example.invalid/rivergauge

go 1.23

require (
	example.invalid/tidewrite/v4 v4.2.0
	gopkg.in/yaml.v3 v3.0.1
)
MOD

cat >cmd/ingest/main.go <<'GO'
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

const (
	checkEvery  = 20 * time.Second
	maxBadCheck = 3
)

type sample struct {
	GaugeID string    `json:"gauge_id"`
	TakenAt time.Time `json:"taken_at"`
	LevelMM float64   `json:"level_mm"`
}

func main() {
	writer, err := newWriter(os.Getenv("GAUGE_DB"))
	if err != nil {
		log.Fatal(err)
	}
	go watchDatabase(writer)

	http.HandleFunc("/samples", func(w http.ResponseWriter, r *http.Request) {
		var batch []sample
		if err := json.NewDecoder(r.Body).Decode(&batch); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		for _, s := range batch {
			writer.Enqueue(s.GaugeID, s.TakenAt, s.LevelMM)
		}
		w.WriteHeader(http.StatusAccepted)
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func watchDatabase(writer *gaugeWriter) {
	bad := 0
	for range time.Tick(checkEvery) {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err := writer.Ping(ctx)
		cancel()
		if err == nil {
			bad = 0
			continue
		}
		bad++
		log.Printf("database check %d failed: %v", bad, err)
		if bad >= maxBadCheck {
			log.Fatalf("database unreachable after %d checks", bad)
		}
	}
}
GO

cat >cmd/ingest/writer.go <<'GO'
package main

import (
	"context"
	"time"

	"example.invalid/tidewrite/v4"
)

const insertSample = `INSERT INTO samples (gauge_id, taken_at, level_mm)
VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`

type gaugeWriter struct {
	client *tidewrite.Client
}

func newWriter(dsn string) (*gaugeWriter, error) {
	client, err := tidewrite.Open(dsn,
		tidewrite.WithStatement(insertSample),
		tidewrite.WithBuffer(50000),
		tidewrite.WithFlushEvery(5*time.Second),
	)
	if err != nil {
		return nil, err
	}
	return &gaugeWriter{client: client}, nil
}

func (w *gaugeWriter) Enqueue(gaugeID string, takenAt time.Time, levelMM float64) {
	w.client.Enqueue(gaugeID, takenAt, levelMM)
}

func (w *gaugeWriter) Ping(ctx context.Context) error {
	return w.client.Ping(ctx)
}
GO

cat >config/sites.yaml <<'YAML'
sample_hz: 2
sites:
  - name: north-weir
    gauges: 60
  - name: mill-bridge
    gauges: 40
  - name: lower-reach
    gauges: 20
YAML

cat >db/schema.sql <<'SQL'
CREATE TABLE samples (
  gauge_id  TEXT             NOT NULL,
  taken_at  TIMESTAMPTZ      NOT NULL,
  level_mm  DOUBLE PRECISION NOT NULL,
  PRIMARY KEY (gauge_id, taken_at)
);
SQL

cat >deploy/ingest.service <<'INI'
[Unit]
Description=River gauge ingest
After=network-online.target

[Service]
ExecStart=/opt/rivergauge/ingest
EnvironmentFile=/etc/rivergauge/ingest.env
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
INI

cat >docs/vendor/tidewrite-changelog.md <<'MD'
# Tidewrite changelog

## 4.2.0

- A failed flush is retried with backoff until it succeeds, in order.

## 4.0.0

- Ring storage: the index type is now a uint16.
- `WithBuffer(n)`: n is stored in that index type; a larger n takes the type's maximum.
- Queued rows live in process memory.
- When the ring is full, a new row overwrites the oldest.
MD

cat >docs/vendor/streamsink-notes.md <<'MD'
# Streamsink notes

A Go client for batched database writes.

- `WithSpool(dir, maxBytes)` queues rows in segment files on local disk.
- Spooled rows are replayed in order after a process start.
- Same `Enqueue` and `WithFlushEvery` shape as other batch writers.
- Go 1.22 or later.
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: C
reason: the Brief names the write-path decision and its options; no type or module design is open
---
MD

cat >.work/review-target/PLAN.md <<'MD'
# River gauge ingest during database outages

## Brief

### Problem

Gauges post water levels to the ingest service, and the flood desk reads them from the samples
table. During last spring's two database maintenance windows, the desk found gaps in the readings
for the hours around the window. We need ingest to ride out an outage of the size we actually see.

### Goal

Decide whether Tidewrite stays as the ingest write client, and close the outage gaps.

### Acceptance criteria

- AC1: No sample accepted by `/samples` during a database outage of up to 30 minutes is missing
  from the samples table once the database returns.
- AC2: With the database healthy, an accepted sample reaches the table within 10 seconds.
- AC3: The on-call engineer can read the number of queued samples from a metric.

### Out-of-scope

- Gauge firmware and the gauge-side retry behaviour.
- The flood desk dashboards.
- Database high availability.

### Captured assumptions

- Quality bar: production
- Ingest stays one Go service on one host.
- Gauge count stays at the 120 in `config/sites.yaml` for the next year.

## Plan

### Decision

Keep Tidewrite as the write client and size its queue for the longest outage in AC1.

### Why

- Tidewrite is the write client in `cmd/ingest/writer.go`, and the team has run it in production for
  three years. Its behaviour under load is known and its settings are in our runbook.
- A different client would mean relearning those settings and rewriting the runbook for no change
  in what the flood desk sees.

### Phase 1: Size the queue for a 30-minute outage [TODO]

**Satisfies:** AC1

`config/sites.yaml` gives 120 gauges at 2 samples per second, or 240 samples per second, which is
432,000 samples in 30 minutes. Change `newWriter` in `cmd/ingest/writer.go` to
`tidewrite.WithBuffer(500000)`, which holds the full 30 minutes with some margin.

**Sanity Check:** in staging, stop the database for 30 minutes under replayed gauge traffic, restart
it, and compare the row count against the replay log.

### Phase 2: Keep the flush path as it is [TODO]

**Satisfies:** AC1, AC2

Leave `WithFlushEvery` at 5 seconds, which holds AC2. Tidewrite 4.2 retries a failed flush, and a
retried batch is harmless here: the primary key on `(gauge_id, taken_at)` and `ON CONFLICT DO
NOTHING` in `insertSample` make a re-sent row a no-op.

**Sanity Check:** with the database healthy, sample latency from request to row stays under
10 seconds at the replayed rate.

### Phase 3: Queue depth metric [TODO]

**Satisfies:** AC3

Add a `gauge_queue_depth` gauge on a `/metrics` endpoint in `cmd/ingest/main.go`, read from the
Tidewrite client's `Depth()`.

**Sanity Check:** the metric climbs during the staging outage and falls back to zero after.

### Load-bearing assumptions

- Outages stay at or below 30 minutes, which matches both windows last spring.
- At about 64 bytes a row, the queue adds roughly 32 MB to the service's memory.

### Test strategy

- Unit: `newWriter` passes the configured options; the handler enqueues each sample in a batch.
- Integration: the staging outage drill in Phase 1, with the row count compared to the replay log.
- Latency: the Phase 2 measurement at the replayed rate.
MD
