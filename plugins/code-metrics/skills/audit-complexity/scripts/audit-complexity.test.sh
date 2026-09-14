#!/usr/bin/env bash
# Regression tests for the audit-complexity entry point (audit-complexity.sh):
# option parsing, the references it prints with their provenance, the lanes it
# reports as unavailable, and exit-code passthrough from dispatch.sh.
# Collectors are stubbed at runtime: a temporary bin/ prepended to a filtered
# PATH carries fake `lizard`, `radon`, `multimetric`, `gocognit` and
# `shellmetrics` replaying the committed captures under
# fixtures/tool-output/ (design T13; nothing executable is committed).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-complexity.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
CAPTURES="$PLUGIN_ROOT/scripts/fixtures/tool-output"
cd "$REPO_ROOT" || exit 2

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH"' EXIT
# The markdown path persists the document; keep it out of the real data
# directory.
export CODE_METRICS_REPORT_DIR="$STUBS/reports"

cat >"$STUBS/lizard" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '1.24.0\n'; exit 0; fi
cat "$CAPTURES/lizard.csv"
EOF
cat >"$STUBS/radon" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '6.0.1\n'; exit 0; fi
if [[ "\${1:-}" == "cc" ]]; then cat "$CAPTURES/radon-cc.json"; exit 0; fi
if [[ "\${1:-}" == "hal" ]]; then cat "$CAPTURES/radon-hal.json"; exit 0; fi
exit 0
EOF
cat >"$STUBS/multimetric" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '2.4.4\n'; exit 0; fi
cat "$CAPTURES/multimetric.json"
EOF
cat >"$STUBS/gocognit" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in -version | --version) printf 'v1.2.1\n'; exit 0 ;; esac
cat "$CAPTURES/gocognit.json"
EOF
cat >"$STUBS/shellmetrics" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '0.5.0\n'; exit 0; fi
cat "$CAPTURES/shellmetrics.csv"
EOF
chmod +x "$STUBS"/*

# EMPTY_PATH is the caller's PATH with every collector removed: a directory of
# symlinks to each executable on PATH except the tools the ladder names (and
# the binaries those adapters look up), so the coreutils, git and the
# interpreter stay reachable while a real lizard, radon, eslint or gocyclo on
# this machine cannot shadow the stubs or the assertions.
# shellcheck source=../../../scripts/tool-free-path.sh
source "$PLUGIN_ROOT/scripts/tool-free-path.sh"
cm_assert_tool_free_path "$EMPTY_PATH"
unset CODE_METRICS_DISABLE_BUNDLED

# 1. Every stub resolves: the document, its references, and its run table.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "--json exits 0" 0 "$rc"
assert_doc "--json prints a code-metrics/v1 document for audit-complexity" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-complexity" and d["run"]'
assert_doc "cyclomatic cites ISO/IEC 5055 8.2.117 at a reference of 20" "$out" \
  'any(t["measure"]=="cyclomatic" and t["reference"]==20 and "8.2.117" in t["provenance"] for t in d["thresholds"])'
assert_doc "cognitive and halstead_difficulty have no reference" "$out" \
  'all(t["reference"] is None for t in d["thresholds"] if t["measure"] in ("cognitive","halstead_difficulty")) and len([t for t in d["thresholds"] if t["measure"] in ("cognitive","halstead_difficulty")])==2'
assert_doc "python cognitive is unavailable, not silent" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="cognitive" and r["status"]=="unavailable" and r["reason"] for r in d["run"])'
assert_doc "bash cognitive is unavailable, not silent" "$out" \
  'any(r["lane"]=="bash" and r["measure"]=="cognitive" and r["status"]=="unavailable" and r["reason"] for r in d["run"])'
assert_doc "the python fixture carries function ranges for the CRAP join" "$out" \
  'any(r["file"].endswith("cm_sample.py") and r["start_line"]==9 and r["end_line"]==20 for r in d["measures"])'
assert_doc "the go lane reports cognitive complexity from gocognit" "$out" \
  'any(r["lane"]=="go" and r["values"].get("cognitive")==2 for r in d["measures"])'
assert_doc "the bash lane reports cyclomatic complexity from shellmetrics" "$out" \
  'any(r["lane"]=="bash" and r["values"].get("cyclomatic")==3 for r in d["measures"])'
assert_doc "halstead difficulty is reported and never fabricated as zero" "$out" \
  'all(r["values"]["halstead_difficulty"] for r in d["measures"] if "halstead_difficulty" in r["values"])'
# The five lane fixtures by name (cm-sample.ts, cm_sample.py, cm-sample.sh,
# cm-sample.go, CmSample.cs): the assertion is also what maps them to this suite.
assert_doc "the four measurable fixtures are measured and CmSample.cs is deferred" "$out" \
  'sorted({r["file"].rsplit("/",1)[1] for r in d["measures"]})==["cm-sample.go","cm-sample.sh","cm-sample.ts","cm_sample.py"] and any(r["lane"]=="dotnet" and r["status"]=="deferred" for r in d["run"])'

# 2. The markdown rendering opens with the coverage table.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "Coverage of this run"
assert_contains "markdown carries the cited cyclomatic reference" "$out" "8.2.117"
assert_contains "markdown states that a reference is not a bar" "$out" "never a bar"
assert_contains "markdown carries the Labels column" "$out" "| File | Function | Lane | Labels |"
assert_contains "markdown names the persisted document" "$out" "Full document: $CODE_METRICS_REPORT_DIR/audit-complexity-"
doc_path="$(printf '%s\n' "$out" | sed -n 's/^Full document: //p')"
"$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); raise SystemExit(0 if d["schema"]=="code-metrics/v1" and d["skill"]=="audit-complexity" else 1)' "$doc_path"
assert_eq "the persisted document is the code-metrics/v1 JSON the markdown was rendered from" 0 "$?"
err="$(PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_REPORT_DIR=/proc/code-metrics-cannot-write bash "$SCRIPT" --all "$SOURCES" 2>&1 >/dev/null)"
rc=$?
assert_eq "an unwritable report directory does not fail the run" 0 "$rc"
assert_contains "an unwritable report directory is named on stderr with the --json remedy" "$err" "not writable"
out="$(PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_REPORT_DIR=/proc/code-metrics-cannot-write bash "$SCRIPT" --all "$SOURCES" 2>/dev/null)"
case "$out" in
*"Full document:"*) fail "no document line when nothing was persisted" "no Full document line" "$(printf '%s' "$out" | tail -3)" ;;
*) pass "no document line when nothing was persisted" ;;
esac

# 3. Every collector absent: exit 0, status empty, nothing measured silently.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when no collector resolved" 0 "$rc"
assert_doc "status empty and every run row non-ok with a reason" "$out" \
  'd["status"]=="empty" and d["run"] and all(r["status"]!="ok" and r["reason"] for r in d["run"]) and d["measures"]==[]'
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES")"
assert_contains "the all-unavailable run renders the Measured nothing headline" "$out" "Measured nothing"

# 4. Usage.
PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit path exits 2" 2 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --help 2>&1 | grep -q 'audit-complexity.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
