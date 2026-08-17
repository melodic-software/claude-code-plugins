#!/usr/bin/env bash
# Black-box contract test for measure.mjs — the offline surfaces only.
#
# Covers: the /context markdown parser (current-format fixture, the
# stdin-warning trap, loud refusal on an unrecognized format), compare's
# comparability rules (identical runs comparable; skill-listing signature
# mismatch marks System tools incomparable; schema validation), and the
# ledger (one file per run plus an appended history line; schema-checked
# append). The live sdk / cli-parse measurement paths spawn a real Claude
# Code binary and are exercised manually, not here — this suite must stay
# hermetic.
#
# Prerequisites: node on PATH (the engine's own runtime — required for
# correctness; absent, this suite fails loudly rather than skipping).
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/measure.mjs"
FIXTURE="$SCRIPT_DIR/fixtures/context-sample.md"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required to test the engine" >&2
  exit 1
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# jsonget <file> <js-expression over parsed `j`> — prints the value
jsonget() {
  node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const v=(function(){return eval(process.argv[2])})();process.stdout.write(String(v))" "$1" "$2"
}

# write_snapshot <file> <mode> <version> <signature> <systemtools> <skilltokens>
# Minimal but schema-valid snapshot record for compare tests.
write_snapshot() {
  printf '{"schema":"context-budget.snapshot/1","timestampUtc":"2026-01-01T00:00:00Z","mode":"%s","precision":"exact","label":null,"deny":[],"binary":{"path":"/opt/fake/claude","version":"%s"},"categories":{"System tools":%s,"System tools (deferred)":1000,"Skills":%s},"totalTokens":%s,"skillListing":{"signature":"%s","tokens":%s,"rows":3}}\n' \
    "$2" "$3" "$5" "$6" "$5" "$4" "$6" >"$1"
}

# --- parse-context: current-format fixture --------------------------------

out="$WORK/parsed.json"
node "$ENGINE" parse-context --file "$FIXTURE" --out "$out" >/dev/null
if [[ $? -ne 0 ]]; then
  fail "parse-context exited nonzero on the current-format fixture"
else
  [[ "$(jsonget "$out" 'j.categories["System tools"]')" == "11400" ]] &&
    ok "category cell 11.4k parses to 11400" ||
    fail "category cell 11.4k misparsed: got $(jsonget "$out" 'j.categories["System tools"]')"
  [[ "$(jsonget "$out" 'j.categories["Messages"]')" == "42" ]] &&
    ok "plain integer cell parses exactly" ||
    fail "plain integer cell misparsed"
  [[ "$(jsonget "$out" 'j.precision')" == "display-rounded" ]] &&
    ok "k-suffixed cells mark the record display-rounded" ||
    fail "precision flag wrong for rounded cells"
  [[ "$(jsonget "$out" 'j.skillListing.rows')" == "3" ]] &&
    ok "skill rows collected (including ~ and < cells)" ||
    fail "skill rows wrong: $(jsonget "$out" 'j.skillListing.rows')"
  [[ "$(jsonget "$out" 'j.agents.length')" == "2" ]] &&
    ok "agent rows collected" ||
    fail "agent rows wrong"
  [[ "$(jsonget "$out" 'j.model')" == "claude-test-model" ]] &&
    ok "model line parsed" ||
    fail "model line misparsed"
fi

# --- parse-context: the unredirected-stdin warning trap -------------------

warned="$WORK/warned.md"
{
  echo "Warning: no stdin data received after 3 seconds."
  cat "$FIXTURE"
} >"$warned"
out2="$WORK/parsed2.json"
if node "$ENGINE" parse-context --file "$warned" --out "$out2" >/dev/null &&
  [[ "$(jsonget "$out2" 'j.categories["System tools"]')" == "11400" ]]; then
  ok "leading warning line is stripped before parsing"
else
  fail "warning-line trap not handled"
fi

# --- parse-context: signature is content-derived and stable ---------------

sig1="$(jsonget "$out" 'j.skillListing.signature')"
sig2="$(jsonget "$out2" 'j.skillListing.signature')"
if [[ -n "$sig1" && "$sig1" == "$sig2" ]]; then
  ok "skill-listing signature is deterministic across identical listings"
else
  fail "signature not deterministic: '$sig1' vs '$sig2'"
fi

# --- parse-context: loud refusal on an unrecognized format ----------------

printf 'Totally different output\nwith no markdown tables at all\n' >"$WORK/garbage.md"
gout="$WORK/garbage-out.json"
node "$ENGINE" parse-context --file "$WORK/garbage.md" >"$gout" 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]] && grep -q 'context-budget.error/1' "$gout"; then
  ok "unrecognized format exits 3 with a structured error (never a guessed number)"
else
  fail "unrecognized format: expected exit 3 + error record, got exit $rc"
fi

# A category table that parses but lacks the System tools row must also refuse.
printf '## Context Usage\n\n### Estimated usage by category\n\n| Category | Tokens | Percentage |\n|---|---|---|\n| Something else | 1.0k | 1.0%% |\n' >"$WORK/norow.md"
node "$ENGINE" parse-context --file "$WORK/norow.md" >"$WORK/norow-out.json" 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]] && grep -q 'System tools' "$WORK/norow-out.json"; then
  ok "missing System tools row refuses rather than guessing"
else
  fail "missing System tools row: expected exit 3 naming the row, got exit $rc"
fi

# --- compare: identical runs are comparable, deltas are zero --------------

write_snapshot "$WORK/a.json" sdk 9.9.9 sigAAAA 5000 2000
write_snapshot "$WORK/b.json" sdk 9.9.9 sigAAAA 4000 2000
write_snapshot "$WORK/c.json" sdk 9.9.9 sigBBBB 4000 2000

row="$WORK/row-self.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/a.json" --lever noop --out "$row" >/dev/null
[[ "$(jsonget "$row" 'j.comparability.ok')" == "true" ]] &&
  ok "identical runs compare as comparable" ||
  fail "identical runs flagged incomparable: $(jsonget "$row" 'JSON.stringify(j.comparability.reasons)')"
[[ "$(jsonget "$row" 'j.delta["System tools"]')" == "0" ]] &&
  ok "self-compare delta is zero" ||
  fail "self-compare delta nonzero"

# --- compare: a real delta, signed after-minus-before ---------------------

row2="$WORK/row-delta.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/b.json" --lever "deny:Example" --out "$row2" >/dev/null
[[ "$(jsonget "$row2" 'j.delta["System tools"]')" == "-1000" ]] &&
  ok "delta is after-minus-before (a saving prints negative)" ||
  fail "delta sign/magnitude wrong: $(jsonget "$row2" 'j.delta["System tools"]')"
[[ "$(jsonget "$row2" 'j.comparability.systemToolsComparable')" == "true" ]] &&
  ok "same-signature runs keep System tools comparable" ||
  fail "same-signature runs lost comparability"

# --- compare: signature mismatch poisons the System tools delta -----------

row3="$WORK/row-sig.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/c.json" --out "$row3" >/dev/null
[[ "$(jsonget "$row3" 'j.comparability.systemToolsComparable')" == "false" ]] &&
  ok "skill-listing signature mismatch marks System tools incomparable" ||
  fail "signature mismatch not detected"
grep -q 'skill listing differs' "$row3" &&
  ok "signature mismatch carries its reason in the row" ||
  fail "signature-mismatch reason missing"

# --- compare: every recorded mismatch poisons the predicate ---------------

node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));j.binary.path='/opt/other/claude';fs.writeFileSync(process.argv[2],JSON.stringify(j));" "$WORK/a.json" "$WORK/d.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/d.json" --out "$WORK/row-path.json" >/dev/null
[[ "$(jsonget "$WORK/row-path.json" 'j.comparability.systemToolsComparable')" == "false" ]] &&
  ok "same version but different binary path marks System tools incomparable" ||
  fail "binary-path mismatch not reflected in the predicate"

node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));j.skillListing.tokens=2500;fs.writeFileSync(process.argv[2],JSON.stringify(j));" "$WORK/a.json" "$WORK/e.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/e.json" --out "$WORK/row-skills.json" >/dev/null
[[ "$(jsonget "$WORK/row-skills.json" 'j.comparability.systemToolsComparable')" == "false" ]] &&
  ok "matching listing but moved Skills bucket marks System tools incomparable" ||
  fail "skills-bucket drift not reflected in the predicate"

# --- emit: --out creates missing parent directories -----------------------

deepout="$WORK/fresh/data/dir/parsed.json"
if node "$ENGINE" parse-context --file "$FIXTURE" --out "$deepout" >/dev/null && [[ -f "$deepout" ]]; then
  ok "--out creates its parent directories (fresh data dir does not ENOENT)"
else
  fail "--out into a nonexistent directory failed"
fi

# --- compare: schema validation -------------------------------------------

printf '{"schema":"something-else/9"}\n' >"$WORK/notsnap.json"
node "$ENGINE" compare --before "$WORK/notsnap.json" --after "$WORK/a.json" >/dev/null 2>&1
[[ $? -eq 2 ]] &&
  ok "compare rejects a non-snapshot input as a usage error" ||
  fail "compare accepted a non-snapshot input"

# --- ledger: one file per run plus an appended line -----------------------

LDIR="$WORK/data"
node "$ENGINE" ledger --append "$row2" --dir "$LDIR" >/dev/null &&
  ok "ledger append succeeds on a compare row" ||
  fail "ledger append failed"
runfiles=$(find "$LDIR/runs" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[[ "$runfiles" == "1" ]] &&
  ok "ledger writes one file per run" ||
  fail "expected 1 run file, found $runfiles"
node "$ENGINE" ledger --append "$row" --dir "$LDIR" >/dev/null
lines=$(wc -l <"$LDIR/ledger.jsonl" | tr -d ' ')
[[ "$lines" == "2" ]] &&
  ok "history line appended per run (a rerun never erases the earlier point)" ||
  fail "expected 2 ledger lines, found $lines"

listed="$WORK/listed.json"
node "$ENGINE" ledger --list --dir "$LDIR" >"$listed"
[[ "$(jsonget "$listed" 'j.rows.length')" == "2" ]] &&
  ok "ledger list returns both rows" ||
  fail "ledger list wrong row count"

# Same row appended again (same timestamp + lever): the run file must not be
# overwritten — the runId collides into a numbered suffix.
node "$ENGINE" ledger --append "$row" --dir "$LDIR" >/dev/null
runfiles=$(find "$LDIR/runs" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[[ "$runfiles" == "3" ]] &&
  ok "colliding runId gets a suffix instead of overwriting (3 run files)" ||
  fail "runId collision overwrote: expected 3 run files, found $runfiles"

# --- ledger: schema-checked append ----------------------------------------

node "$ENGINE" ledger --append "$WORK/a.json" --dir "$LDIR" >/dev/null 2>&1
[[ $? -eq 2 ]] &&
  ok "ledger rejects a non-ledger row (snapshots are not ledger rows)" ||
  fail "ledger accepted a snapshot as a row"

node "$ENGINE" ledger --append "$row" --dir "relative/dir" >/dev/null 2>&1
[[ $? -eq 2 ]] &&
  ok "ledger rejects a relative --dir" ||
  fail "ledger accepted a relative --dir"

# --- snapshot: pinned-binary honesty --------------------------------------

node "$ENGINE" snapshot --binary "$WORK/does-not-exist" >"$WORK/nobin.json" 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]] && grep -q 'binary-not-found' "$WORK/nobin.json"; then
  ok "snapshot with a missing --binary degrades with a structured error"
else
  fail "missing --binary: expected exit 3 + binary-not-found, got exit $rc"
fi

# --- summary ---------------------------------------------------------------

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
