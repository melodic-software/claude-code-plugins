#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p cmd/stockd cmd/stockctl internal/server internal/store internal/warehouse config .work/review-target/design

cat >go.mod <<'MOD'
module example.invalid/stockd

go 1.22

require gopkg.in/yaml.v3 v3.0.1
MOD

cat >cmd/stockctl/main.go <<'GO'
package main

import (
    "bufio"
    "fmt"
    "net"
    "os"
    "strings"
)

func main() {
    conn, err := net.Dial("unix", "stockd.sock")
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    defer conn.Close()
    fmt.Fprintln(conn, strings.Join(os.Args[1:], " "))
    reply, err := bufio.NewReader(conn).ReadString('\n')
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    fmt.Print(reply)
    if strings.HasPrefix(reply, "error:") {
        os.Exit(1)
    }
}
GO

cat >cmd/stockd/main.go <<'GO'
package main

import (
    "log"
    "net"
    "os"

    "example.invalid/stockd/internal/server"
    "example.invalid/stockd/internal/store"
    "example.invalid/stockd/internal/warehouse"
)

func main() {
    cfg, err := warehouse.Load("config/warehouse.yaml")
    if err != nil {
        log.Fatalf("config: %v", err)
    }
    st, err := store.Open("data")
    if err != nil {
        log.Fatalf("store: %v", err)
    }
    _ = os.Remove("stockd.sock")
    listener, err := net.Listen("unix", "stockd.sock")
    if err != nil {
        log.Fatalf("listen: %v", err)
    }
    log.Fatal(server.New(st, cfg).Serve(listener))
}
GO

cat >internal/server/server.go <<'GO'
package server

import (
    "bufio"
    "fmt"
    "net"
    "strconv"
    "strings"
    "sync"

    "example.invalid/stockd/internal/store"
    "example.invalid/stockd/internal/warehouse"
)

type Server struct {
    mu    sync.Mutex
    store *store.Store
    cfg   *warehouse.Config
}

func New(st *store.Store, cfg *warehouse.Config) *Server {
    return &Server{store: st, cfg: cfg}
}

func (s *Server) Serve(listener net.Listener) error {
    for {
        conn, err := listener.Accept()
        if err != nil {
            return err
        }
        go func() {
            defer conn.Close()
            line, err := bufio.NewReader(conn).ReadString('\n')
            if err != nil {
                return
            }
            fmt.Fprintln(conn, s.handle(strings.Fields(line)))
        }()
    }
}

func (s *Server) handle(args []string) string {
    s.mu.Lock()
    defer s.mu.Unlock()
    if len(args) == 0 {
        return "error: empty command"
    }
    switch args[0] {
    case "show":
        return strconv.Itoa(s.store.OnHand(args[1]))
    case "adjust":
        delta, err := strconv.Atoi(args[2])
        if err != nil {
            return "error: delta"
        }
        if err := s.adjust(args[1], delta, args[3]); err != nil {
            return "error: " + err.Error()
        }
        return "ok"
    }
    return "error: unknown command"
}

func (s *Server) adjust(bin string, delta int, reason string) error {
    entry := s.store.NextEntry(bin, delta, reason)
    if err := s.store.AppendJournal(entry); err != nil {
        return err
    }
    s.store.Apply(entry)
    return s.store.SaveBins()
}
GO

cat >internal/store/store.go <<'GO'
package store

import (
    "bufio"
    "encoding/json"
    "errors"
    "fmt"
    "os"
    "path/filepath"
)

type Entry struct {
    Seq    int64  `json:"seq"`
    Bin    string `json:"bin"`
    Delta  int    `json:"delta"`
    Reason string `json:"reason"`
}

type snapshot struct {
    Seq  int64          `json:"seq"`
    Bins map[string]int `json:"bins"`
}

type Store struct {
    dir  string
    snap snapshot
}

// Open loads bins.json and brings it level with the journal.
func Open(dir string) (*Store, error) {
    s := &Store{dir: dir, snap: snapshot{Bins: map[string]int{}}}
    raw, err := os.ReadFile(filepath.Join(dir, "bins.json"))
    if err != nil && !errors.Is(err, os.ErrNotExist) {
        return nil, err
    }
    if err == nil {
        if err := json.Unmarshal(raw, &s.snap); err != nil {
            return nil, err
        }
    }
    entries, err := s.readJournal()
    if err != nil {
        return nil, err
    }
    var last int64
    for _, entry := range entries {
        last = entry.Seq
        if entry.Seq > s.snap.Seq {
            s.Apply(entry)
        }
    }
    if s.snap.Seq > last {
        return nil, fmt.Errorf("bins.json at seq %d, journal ends at seq %d", s.snap.Seq, last)
    }
    return s, s.SaveBins()
}

func (s *Store) OnHand(bin string) int { return s.snap.Bins[bin] }

func (s *Store) NextEntry(bin string, delta int, reason string) Entry {
    return Entry{Seq: s.snap.Seq + 1, Bin: bin, Delta: delta, Reason: reason}
}

func (s *Store) Apply(entry Entry) {
    s.snap.Bins[entry.Bin] += entry.Delta
    s.snap.Seq = entry.Seq
}

// SaveBins replaces bins.json through a temporary file and a rename.
func (s *Store) SaveBins() error {
    raw, err := json.Marshal(s.snap)
    if err != nil {
        return err
    }
    tmp := filepath.Join(s.dir, "bins.json.tmp")
    if err := os.WriteFile(tmp, raw, 0o644); err != nil {
        return err
    }
    return os.Rename(tmp, filepath.Join(s.dir, "bins.json"))
}

func (s *Store) AppendJournal(entries ...Entry) error {
    file, err := os.OpenFile(filepath.Join(s.dir, "journal.ndjson"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
    if err != nil {
        return err
    }
    defer file.Close()
    for _, entry := range entries {
        raw, err := json.Marshal(entry)
        if err != nil {
            return err
        }
        if _, err := fmt.Fprintln(file, string(raw)); err != nil {
            return err
        }
    }
    return file.Sync()
}

func (s *Store) readJournal() ([]Entry, error) {
    file, err := os.Open(filepath.Join(s.dir, "journal.ndjson"))
    if errors.Is(err, os.ErrNotExist) {
        return nil, nil
    }
    if err != nil {
        return nil, err
    }
    defer file.Close()
    var entries []Entry
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        var entry Entry
        if err := json.Unmarshal(scanner.Bytes(), &entry); err != nil {
            return nil, err
        }
        entries = append(entries, entry)
    }
    return entries, scanner.Err()
}
GO

cat >internal/store/store_test.go <<'GO'
package store

import "testing"

func TestOpenRollsForwardFromJournal(t *testing.T) {
    dir := t.TempDir()
    s, err := Open(dir)
    if err != nil {
        t.Fatal(err)
    }
    if err := s.AppendJournal(s.NextEntry("A-01", 20, "receipt")); err != nil {
        t.Fatal(err)
    }
    reopened, err := Open(dir)
    if err != nil {
        t.Fatal(err)
    }
    if got := reopened.OnHand("A-01"); got != 20 {
        t.Fatalf("OnHand = %d, want 20", got)
    }
}
GO

cat >internal/warehouse/config.go <<'GO'
package warehouse

import (
    "os"

    "gopkg.in/yaml.v3"
)

type Bin struct {
    Code       string  `yaml:"code"`
    SKU        string  `yaml:"sku"`
    CapacityKg float64 `yaml:"capacity_kg"`
}

type SKU struct {
    Code   string  `yaml:"code"`
    UnitKg float64 `yaml:"unit_kg"`
}

type Config struct {
    Bins []Bin `yaml:"bins"`
    SKUs []SKU `yaml:"skus"`
}

func Load(path string) (*Config, error) {
    raw, err := os.ReadFile(path)
    if err != nil {
        return nil, err
    }
    var cfg Config
    return &cfg, yaml.Unmarshal(raw, &cfg)
}
GO

cat >config/warehouse.yaml <<'YAML'
skus:
  - code: BOLT-M8
    unit_kg: 0.05
  - code: PLATE-20
    unit_kg: 12.5
bins:
  - code: A-01
    sku: BOLT-M8
    capacity_kg: 400
  - code: A-02
    sku: BOLT-M8
    capacity_kg: 400
  - code: B-01
    sku: PLATE-20
    capacity_kg: 1500
  - code: B-02
    sku: PLATE-20
    capacity_kg: 1000
YAML

cat >.work/review-target/PLAN.md <<'MD'
# Bin-to-bin transfers

## Brief

### Problem
Pickers move stock between bins every shift. `stockctl` has only `adjust`, so a move is two manual
adjustments. Staff make one and forget the other, and on-hand figures drift until the next count.

### Goal
One `stockctl transfer` command moves stock between two bins of the same SKU and records it.

### Acceptance criteria
- AC1: `stockctl transfer <from> <to> <qty>` lowers `<from>` and raises `<to>` by `<qty>`, and the
  journal records both sides under the same reason.
- AC2: A transfer that would put `<to>` over its capacity is refused and changes nothing.
- AC3: A transfer of more than `<from>` holds is refused and changes nothing, with exit code 2.
- AC4: A transfer between bins of different SKUs is refused and changes nothing.

### Out-of-scope
- Multi-warehouse moves.
- Reservations against stock that is being picked.

### Captured assumptions
- Quality bar: production
- One warehouse and one `stockd` process per data directory.

## Plan

### Phase 1: Transfer command [STATUS]
**Satisfies:** AC1

- `stockctl transfer` sends `transfer <from> <to> <qty>` over the socket.
- Add a `transfer` case to `Server.handle` that calls a new `Server.transfer`.
- `Server.transfer` builds and applies a debit entry, then a credit entry, each with `NextEntry`.
  It then calls `store.SaveBins`, then `store.AppendJournal` with the two entries.
- The new case runs inside `Server.handle`, so it holds `s.mu` for the whole command. Two `stockctl`
  processes therefore need no file lock on the data directory.

**Sanity Check:** after `stockctl adjust A-01 20 count` and `stockctl transfer A-01 A-02 5`, `show`
prints 15 and 5 and the last two lines of `data/journal.ndjson` share a reason.

### Phase 2: Capacity and SKU checks [STATUS]
**Satisfies:** AC2, AC4

- Before any write, `Server.transfer` looks up both bins in `warehouse.Config`.
- Refuse when the two `SKU` values differ.
- Refuse when `OnHand(to) + qty` is above the capacity of `<to>`.
- Refusals return an `error:` line with no call to `Apply`, `SaveBins` or `AppendJournal`.

**Sanity Check:** `stockctl transfer A-01 B-01 1` prints an error and both `show` values stay as they
were. With B-02 at capacity less one, a transfer of 2 from B-01 prints an error.

### Phase 3: Overdraw refusal [STATUS]
**Satisfies:** AC3

- `Server.transfer` returns `ErrOverdraw` when `qty` is above `OnHand(from)`, before any write.
- `stockctl` maps a reply beginning `error: overdraw` to exit code 2.

**Sanity Check:** with A-01 at 20, `stockctl transfer A-01 A-02 5` exits 0 and `show A-01` prints 15.
An overdraw regression would show up in that balance.

### Load-bearing assumptions
- `capacity` in `config/warehouse.yaml` counts the same thing as on-hand, so the Phase 2 comparison
  is direct and needs no conversion.
- Every bin that holds stock is listed in `config/warehouse.yaml`.
- `Store.Open` keeps its current behavior; this plan adds no change to how the store loads.

### Test strategy
Go table tests in `internal/server/server_test.go` call `handle` against a store in a temporary
directory, one row per acceptance criterion. `go test ./...` must pass.

### Files affected
| File | Action |
|---|---|
| `cmd/stockctl/main.go` | modify: `transfer` subcommand, exit code mapping |
| `internal/server/server.go` | modify: `transfer` case and `Server.transfer` |
| `internal/server/server_test.go` | create |
MD

# Each phase heading takes its status tag here, outside the heredoc.
plan=.work/review-target/PLAN.md
text="$(cat "$plan")"
printf '%s\n' "${text//'[STATUS]'/[TODO]}" >"$plan"

cat >.work/review-target/design/design-resolution.md <<'MD'
outcome: early-exit
tier: C
reason: The command adds one case to the existing socket protocol and reuses the existing store calls.
MD
