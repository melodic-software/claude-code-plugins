#!/usr/bin/env bash
# test-scope: docs/conventions/lifecycle-map/README.md .claude-plugin/marketplace.json .github/workflows/**
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-lifecycle-map.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

scratch=""
fixture_tree::build scratch --label lifecycle-map

expect() {
  local label="$1" want_rc="$2" want_text="$3"
  shift 3
  local out rc
  out="$(bash "$SCRIPT" "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
    return
  fi
  if [[ -n "$want_text" && "$out" != *"$want_text"* ]]; then
    fail "$label: expected output to contain '$want_text', got '$out'"
    return
  fi
  ok "$label"
}

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/.github/workflows" "$dir/.claude-plugin" "$dir/docs/conventions/lifecycle-map"
  : >"$dir/.github/workflows/ci.yml"
  : >"$dir/.github/workflows/triage.yml"
  : >"$dir/.github/workflows/verify.yml"
  cat >"$dir/.claude-plugin/marketplace.json" <<'JSON'
{
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha" },
    { "name": "beta", "source": "./plugins/beta" }
  ]
}
JSON
  cat >"$dir/docs/conventions/lifecycle-map/README.md" <<'MD'
# Lifecycle map

## Intake

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Gate | step in `triage.yml` | tracker | no | issues | labels | gate |
| Verdict | step in `triage.yml` | tracker | yes | gate | issue | verdict |

## Pull request checks

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Required CI (`ci.yml`) | own run | runner | no | pull_request | diff | status |
| Verify (`verify.yml`) | own run after `ci.yml` | runner | yes | after ci | diff | verdict |

## Plugins

### On the map

| Plugin | Tasks that use it, and how |
|---|---|
| `alpha` | Required CI runs it |

### Not an automated task

`beta`.
MD
}

run_fixture() {
  local dir="$1"
  shift
  expect "$@" --check \
    --map "$dir/docs/conventions/lifecycle-map/README.md" \
    --marketplace "$dir/.claude-plugin/marketplace.json" \
    --workflows-dir "$dir/.github/workflows"
}

expect "unknown option exits 2 with usage" 2 "usage:" --bogus
expect "missing map file exits 2" 2 "map file not found" --check --map "$scratch/no-map.md"
expect "missing marketplace file exits 2" 2 "marketplace file not found" --check --marketplace "$scratch/no-mp.json"
expect "missing workflows dir exits 2" 2 "workflows directory not found" --check --workflows-dir "$scratch/no-wf"

f="$scratch/clean"
make_fixture "$f"
run_fixture "$f" "matching map, marketplace and workflows pass" 0 "matches all 3 workflow(s) and all 2 plugin(s)"

f="$scratch/missing-plugin"
make_fixture "$f"
cat >"$f/.claude-plugin/marketplace.json" <<'JSON'
{
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha" },
    { "name": "beta", "source": "./plugins/beta" },
    { "name": "gamma", "source": "./plugins/gamma" }
  ]
}
JSON
run_fixture "$f" "plugin added to marketplace without a map entry fails" 1 "MISSING PLUGIN: 'gamma'"

f="$scratch/dup-plugin-same"
make_fixture "$f"
awk '
  /^\| `alpha`/ { print; print "| `alpha` | Listed twice |"; next }
  { print }
' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "plugin listed twice in On the map fails" 1 "DUPLICATE PLUGIN: 'alpha'"

f="$scratch/dup-plugin-both"
make_fixture "$f"
awk '
  /^`beta`\./ { print "`alpha`, `beta`."; next }
  { print }
' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "plugin listed in both On the map and Not an automated task fails" 1 "DUPLICATE PLUGIN: 'alpha'"

f="$scratch/stale-plugin"
make_fixture "$f"
awk '
  /^`beta`\./ { print "`beta`, `ghost`."; next }
  { print }
' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "plugin in map absent from marketplace fails as stale" 1 "STALE PLUGIN: 'ghost'"

f="$scratch/missing-wf"
make_fixture "$f"
: >"$f/.github/workflows/unmapped.yml"
run_fixture "$f" "workflow file missing from map fails" 1 "MISSING WORKFLOW: 'unmapped.yml'"

f="$scratch/missing-wf-only-referenced-in-after"
make_fixture "$f"
awk '!/Required CI/' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "workflow mentioned only in own run after still fails as missing" 1 "MISSING WORKFLOW: 'ci.yml'"

f="$scratch/dup-wf-task"
make_fixture "$f"
awk '
  /Required CI/ { print; print "| Required CI again (`ci.yml`) | own run | runner | no | push | diff | status |"; next }
  { print }
' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "workflow listed twice in Task cells fails" 1 "DUPLICATE WORKFLOW: 'ci.yml'"

f="$scratch/dup-wf-step"
make_fixture "$f"
awk '
  /^\| Gate \|/ { print; print; next }
  { print }
' "$scratch/clean/docs/conventions/lifecycle-map/README.md" >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "duplicate step row for same workflow fails" 1 "DUPLICATE WORKFLOW ROW: 'triage.yml'"

f="$scratch/stale-wf"
make_fixture "$f"
rm "$f/.github/workflows/verify.yml"
run_fixture "$f" "workflow in map deleted from disk fails as stale" 1 "STALE WORKFLOW: 'verify.yml'"

f="$scratch/missing-heading"
make_fixture "$f"
printf '# Lifecycle map\n\nNo sections.\n' >"$f/docs/conventions/lifecycle-map/README.md"
run_fixture "$f" "map missing required headings exits 2" 2 "missing ## Plugins heading"

f="$scratch/bad-json"
make_fixture "$f"
printf 'not json\n' >"$f/.claude-plugin/marketplace.json"
run_fixture "$f" "malformed marketplace.json exits 2" 2 "failed to read plugin names"

expect "live repository lifecycle map passes parity check" 0 "matches all" --check

test_harness::report
