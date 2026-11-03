#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p cmd/scanhub internal/config internal/ingest config deploy .work/review-target/design

cat > go.mod <<'EOF'
module example.invalid/scanhub

go 1.22

require gopkg.in/yaml.v3 v3.0.1
EOF

cat > internal/config/config.go <<'EOF'
// Package config holds scanhub's runtime settings.
package config

import (
	"log"
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

// Config is one scanhub process's settings.
type Config struct {
	Site         string `yaml:"site"`
	ListenAddr   string `yaml:"listen_addr"`
	SinkURL      string `yaml:"sink_url"`
	BatchSize    int    `yaml:"batch_size"`
	FlushSeconds int    `yaml:"flush_seconds"`
}

// Defaults returns the settings used before any file is read.
func Defaults() Config {
	return Config{ListenAddr: ":7400", BatchSize: 100, FlushSeconds: 10}
}

// Load reads the YAML file at path onto the defaults.
func Load(path string) Config {
	cfg := Defaults()
	raw, err := os.ReadFile(path)
	if err != nil {
		log.Printf("config: read %s: %v, using defaults", path, err)
		return Defaults()
	}
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		log.Printf("config: parse %s: %v, using defaults", path, err)
		return Defaults()
	}
	return cfg
}

// ApplyEnv copies the SCANHUB_* variables that are set onto cfg.
func ApplyEnv(cfg Config) Config {
	if v, err := strconv.Atoi(os.Getenv("SCANHUB_BATCH_SIZE")); err == nil {
		cfg.BatchSize = v
	}
	if v, err := strconv.Atoi(os.Getenv("SCANHUB_FLUSH_SECONDS")); err == nil {
		cfg.FlushSeconds = v
	}
	if v := os.Getenv("SCANHUB_SINK_URL"); v != "" {
		cfg.SinkURL = v
	}
	return cfg
}
EOF

cat > internal/config/config_test.go <<'EOF'
package config

import (
	"testing"

	"gopkg.in/yaml.v3"
)

func TestDecodeOntoPopulatedStructKeepsOtherFields(t *testing.T) {
	cfg := Config{Site: "base", BatchSize: 100, FlushSeconds: 10}
	if err := yaml.Unmarshal([]byte("batch_size: 40\n"), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.BatchSize != 40 || cfg.FlushSeconds != 10 || cfg.Site != "base" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}
EOF

cat > internal/ingest/batch.go <<'EOF'
// Package ingest groups scan events and posts them to the inventory sink.
package ingest

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Scan is one barcode read from a handheld scanner.
type Scan struct {
	Barcode string    `json:"barcode"`
	Scanner string    `json:"scanner"`
	At      time.Time `json:"at"`
}

// Batcher posts scans to sinkURL when size is reached or the interval passes.
type Batcher struct {
	SinkURL string
	Size    int
	Every   time.Duration
	In      chan Scan
}

// Run batches until ctx ends, then flushes what it holds.
func (b *Batcher) Run(ctx context.Context) error {
	tick := time.NewTicker(b.Every)
	defer tick.Stop()
	pending := make([]Scan, 0, b.Size)
	for {
		select {
		case scan := <-b.In:
			pending = append(pending, scan)
			if len(pending) >= b.Size {
				if err := b.post(pending); err != nil {
					return err
				}
				pending = pending[:0]
			}
		case <-tick.C:
			if len(pending) > 0 {
				if err := b.post(pending); err != nil {
					return err
				}
				pending = pending[:0]
			}
		case <-ctx.Done():
			return b.post(pending)
		}
	}
}

func (b *Batcher) post(scans []Scan) error {
	body, err := json.Marshal(scans)
	if err != nil {
		return err
	}
	resp, err := http.Post(b.SinkURL, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("sink returned %s", resp.Status)
	}
	return nil
}
EOF

cat > cmd/scanhub/main.go <<'EOF'
// Command scanhub receives handheld scans and forwards them in batches.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"example.invalid/scanhub/internal/config"
	"example.invalid/scanhub/internal/ingest"
)

func main() {
	path := flag.String("config", "/etc/scanhub/base.yaml", "path to the settings file")
	flag.Parse()

	cfg := config.ApplyEnv(config.Load(*path))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	batcher := &ingest.Batcher{
		SinkURL: cfg.SinkURL,
		Size:    cfg.BatchSize,
		Every:   time.Duration(cfg.FlushSeconds) * time.Second,
		In:      make(chan ingest.Scan, 1024),
	}

	http.HandleFunc("/scan", func(w http.ResponseWriter, r *http.Request) {
		var scan ingest.Scan
		if err := json.NewDecoder(r.Body).Decode(&scan); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		batcher.In <- scan
		w.WriteHeader(http.StatusAccepted)
	})
	go func() { log.Fatal(http.ListenAndServe(cfg.ListenAddr, nil)) }()

	if err := batcher.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
EOF

cat > config/base.yaml <<'EOF'
listen_addr: ":7400"
sink_url: "http://inventory.internal/api/scans"
batch_size: 100
flush_seconds: 10
EOF

cat > deploy/docker-compose.yml <<'EOF'
services:
  scanhub:
    image: registry.example.invalid/scanhub:1.14.2
    restart: unless-stopped
    ports:
      - "7400:7400"
    environment:
      SCANHUB_BATCH_SIZE: "200"
      SCANHUB_FLUSH_SECONDS: "30"
    volumes:
      - ./base.yaml:/etc/scanhub/base.yaml:ro
EOF

cat > .work/review-target/PLAN.md <<'EOF'
# Plan: per-site scanhub tuning

## Brief

### Problem

Every warehouse runs the same `scanhub` image with the settings baked into `config/base.yaml`. The
sites differ: the large cross-dock site scans about thirty times what the two returns sites scan.
Today a tuning change to the batch size or the flush interval means editing the shared file and
sending it to all nine sites, so sites live with values chosen for somebody else, and the returns
sites wait far longer than they should for scans to reach inventory.

### Goal

A site's operations lead can tune that site's batching without engineering shipping anything.

### Acceptance criteria

- AC1: Changing a site's batch size or flush interval takes editing one file on that site's host
  and restarting the container, and the new values are then the ones the batcher uses.
- AC2: An overlay file with a YAML error stops `scanhub` at startup with a message naming the file.
- AC3: `scanhub --print-config` prints the values the process would run with, then exits.
- AC4: A site with no overlay file runs with the same values it has today.

### Out-of-scope

- Applying a settings change to a process that is already running; a restart at shift change is
  acceptable to the sites.
- A central service or UI for managing settings.
- Changing the scan event format or the sink API.

### Captured assumptions

- Quality bar: production
- Sites deploy with `deploy/docker-compose.yml`, one copy per site host.

## Proposal

### Recommendation

Add a second, optional layer of the same YAML: `/etc/scanhub/site.yaml`, mounted from the site host,
with the same keys as `config/base.yaml`. A site's file holds only what it changes:

```yaml
site: returns-east
batch_size: 20
flush_seconds: 3
```

`main` gains an `--overlay` flag. After reading the base file it decodes the overlay into the same
`Config` value with `yaml.Unmarshal`. Keys the overlay names take the overlay's value, and every
other field keeps what the base file gave it. A missing overlay file is normal and means no change.

`--print-config` marshals the resulting `Config` back to YAML on stdout.

A SIGHUP handler in `main` re-reads both files and swaps the `Config` behind an `atomic.Pointer`,
with the batcher reading its size and interval through that pointer, so a lead's edit can land
mid-shift with no dropped scanner connections.

### Why this approach

Same format, same keys and same library as the base file, so there is nothing new to learn and no
new dependency. One file per site is the smallest unit a site lead can own, and it can live with
the compose file on that host.

Decoding onto the populated struct gives the layering for almost no code. `Config` is five flat
fields, and `TestDecodeOntoPopulatedStructKeepsOtherFields` in `internal/config/config_test.go`
already pins the behavior this depends on.

### Alternatives considered

- **Viper.** It layers files for us, at the cost of a large dependency tree for the two extra lines
  it would save on a struct this small.
- **One file per site inside the image.** Tuning would still need a release, which is the problem.
- **A settings table in the inventory database.** It would make a warehouse's scanning depend on
  a database it reaches over a wide-area link, at the moment it starts up.

### Load-bearing assumptions

- `config.Load` exits the process on a file it cannot read or parse, so overlays reuse it and AC2
  needs no new error path.
- The batch size and flush interval reach the batcher from the YAML files and from nowhere else.
- Nine sites is the expected count for the next two years; each file is edited a few times a year.

### Rollout

1. Merge the flag, the layering, `--print-config` and the SIGHUP handler.
2. Add the overlay mount to `deploy/docker-compose.yml`.
3. Pilot on `returns-east` with `batch_size: 20`, watching time-to-inventory for one week.
4. Write the one-page guide for site leads, including `docker kill -s HUP scanhub`, and roll out to
   the other eight sites as each asks.
EOF

cat > .work/review-target/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One optional file layer inside a single process, with no new contract between components.
EOF
