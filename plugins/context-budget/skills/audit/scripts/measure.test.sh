#!/usr/bin/env bash
# Black-box contract test for measure.mjs — the offline surfaces only.
#
# Covers: the /context markdown parser (current-format fixture, the
# stdin-warning trap, loud refusal on an unrecognized format), compare's
# comparability rules (identical runs comparable; skill-listing signature
# mismatch marks System tools incomparable; schema validation), the ledger
# (one file per run plus an appended history line; schema-checked append),
# the attribute/additivity pipeline in cli-parse mode against a fake
# `claude` binary (a vanished bucket is unmeasured and incomparable, never a
# coerced zero), and verify-catalogue (binary-scan present/absent, never
# invents presence). The sdk measurement path spawns a real Claude Code
# binary and is exercised manually, not here — this suite must stay hermetic.
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
# assert_eq <actual> <expected> <ok-message> <fail-message>
assert_eq() {
  if [[ "$1" == "$2" ]]; then
    ok "$3"
  else
    fail "$4 (got: $1)"
  fi
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
if ! node "$ENGINE" parse-context --file "$FIXTURE" --out "$out" >/dev/null; then
  fail "parse-context exited nonzero on the current-format fixture"
else
  assert_eq "$(jsonget "$out" 'j.categories["System tools"]')" "11400" \
    "category cell 11.4k parses to 11400" "category cell 11.4k misparsed"
  assert_eq "$(jsonget "$out" 'j.categories["Messages"]')" "42" \
    "plain integer cell parses exactly" "plain integer cell misparsed"
  assert_eq "$(jsonget "$out" 'j.precision')" "display-rounded" \
    "k-suffixed cells mark the record display-rounded" "precision flag wrong for rounded cells"
  assert_eq "$(jsonget "$out" 'j.skillListing.rows')" "3" \
    "skill rows collected (including ~ and < cells)" "skill rows wrong"
  assert_eq "$(jsonget "$out" 'j.agents.length')" "2" \
    "agent rows collected" "agent rows wrong"
  assert_eq "$(jsonget "$out" 'j.model')" "claude-test-model" \
    "model line parsed" "model line misparsed"
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
assert_eq "$(jsonget "$row" 'j.comparability.ok')" "true" \
  "identical runs compare as comparable" "identical runs flagged incomparable"
assert_eq "$(jsonget "$row" 'j.delta["System tools"]')" "0" \
  "self-compare delta is zero" "self-compare delta nonzero"

# --- compare: a real delta, signed after-minus-before ---------------------

row2="$WORK/row-delta.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/b.json" --lever "deny:Example" --out "$row2" >/dev/null
assert_eq "$(jsonget "$row2" 'j.delta["System tools"]')" "-1000" \
  "delta is after-minus-before (a saving prints negative)" "delta sign/magnitude wrong"
assert_eq "$(jsonget "$row2" 'j.comparability.systemToolsComparable')" "true" \
  "same-signature runs keep System tools comparable" "same-signature runs lost comparability"

# --- compare: signature mismatch poisons the System tools delta -----------

row3="$WORK/row-sig.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/c.json" --out "$row3" >/dev/null
assert_eq "$(jsonget "$row3" 'j.comparability.systemToolsComparable')" "false" \
  "skill-listing signature mismatch marks System tools incomparable" "signature mismatch not detected"
if grep -q 'skill listing differs' "$row3"; then
  ok "signature mismatch carries its reason in the row"
else
  fail "signature-mismatch reason missing"
fi

# --- compare: every recorded mismatch poisons the predicate ---------------

node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));j.binary.path='/opt/other/claude';fs.writeFileSync(process.argv[2],JSON.stringify(j));" "$WORK/a.json" "$WORK/d.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/d.json" --out "$WORK/row-path.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-path.json" 'j.comparability.systemToolsComparable')" "false" \
  "same version but different binary path marks System tools incomparable" \
  "binary-path mismatch not reflected in the predicate"

node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));j.skillListing.tokens=2500;fs.writeFileSync(process.argv[2],JSON.stringify(j));" "$WORK/a.json" "$WORK/e.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/e.json" --out "$WORK/row-skills.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-skills.json" 'j.comparability.systemToolsComparable')" "false" \
  "matching listing but moved Skills bucket marks System tools incomparable" \
  "skills-bucket drift not reflected in the predicate"

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
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "compare rejects a non-snapshot input as a usage error"
else
  fail "compare accepted a non-snapshot input (exit $rc)"
fi

# --- ledger: one file per run plus an appended line -----------------------

LDIR="$WORK/data"
if node "$ENGINE" ledger --append "$row2" --dir "$LDIR" >/dev/null; then
  ok "ledger append succeeds on a compare row"
else
  fail "ledger append failed"
fi
runfiles=$(find "$LDIR/runs" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$runfiles" "1" "ledger writes one file per run" "wrong run-file count after first append"
node "$ENGINE" ledger --append "$row" --dir "$LDIR" >/dev/null
lines=$(wc -l <"$LDIR/ledger.jsonl" | tr -d ' ')
assert_eq "$lines" "2" \
  "history line appended per run (a rerun never erases the earlier point)" "wrong ledger line count"

listed="$WORK/listed.json"
node "$ENGINE" ledger --list --dir "$LDIR" >"$listed"
assert_eq "$(jsonget "$listed" 'j.rows.length')" "2" \
  "ledger list returns both rows" "ledger list wrong row count"

# Same row appended again (same timestamp + lever): the run file must not be
# overwritten — the runId collides into a numbered suffix.
node "$ENGINE" ledger --append "$row" --dir "$LDIR" >/dev/null
runfiles=$(find "$LDIR/runs" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$runfiles" "3" \
  "colliding runId gets a suffix instead of overwriting (3 run files)" \
  "runId collision overwrote a run file"

# --- ledger: schema-checked append ----------------------------------------

node "$ENGINE" ledger --append "$WORK/a.json" --dir "$LDIR" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "ledger rejects a non-ledger row (snapshots are not ledger rows)"
else
  fail "ledger accepted a snapshot as a row (exit $rc)"
fi

node "$ENGINE" ledger --append "$row" --dir "relative/dir" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "ledger rejects a relative --dir"
else
  fail "ledger accepted a relative --dir (exit $rc)"
fi

# --- attribute: additivity never coerces a vanished bucket to zero --------
# Hermetic live-path exercise: a fake `claude` binary answers `--version` and
# `-p /context` with deterministic category tables keyed off the deny list and
# FAKE_MODE, so the attribute/additivity pipeline runs end-to-end in cli-parse
# mode with no real Claude Code binary. Run from $WORK so no Agent SDK is
# resolvable and the engine cannot leave cli-parse mode.

FAKEDIR="$WORK/fakebin"
mkdir -p "$FAKEDIR"
cat >"$FAKEDIR/fake-claude.js" <<'EOF'
const args = process.argv.slice(2);
if (args.includes('--version')) { process.stdout.write('9.9.9 (fake)\n'); process.exit(0); }
const di = args.indexOf('--disallowedTools');
const deny = di >= 0 ? args.slice(di + 1) : [];
const key = deny.slice().sort().join('+');
const mode = process.env.FAKE_MODE || 'control';
// Savings per deny set, constructed additive: combined always equals the sum.
const prefixSaved = { AlphaTool: 1000, BetaTool: 600, GammaTool: 500, 'AlphaTool+BetaTool': 1600 };
const deferredSaved = { AlphaTool: 400, BetaTool: 100, GammaTool: 0, 'AlphaTool+BetaTool': 500 };
const table = { 'System tools': 18000 - (prefixSaved[key] ?? 0) };
// The deferred bucket is dropped (omitted, not reported as 0) when:
//   novocab      — this fake "version" has no deferred bucket in any run;
//   vanish       — the combined deny empties it out of the snapshot (#3197);
//   GammaTool    — a single deny empties it out of the snapshot.
const dropDeferred = mode === 'novocab'
  || (mode === 'vanish' && key === 'AlphaTool+BetaTool')
  || key === 'GammaTool';
if (!dropDeferred) table['System tools (deferred)'] = 12000 - (deferredSaved[key] ?? 0);
table.Messages = 42;
const lines = ['## Context Usage', '', '**Model:** fake-model', '',
  '### Estimated usage by category', '',
  '| Category | Tokens | Percentage |', '|---|---|---|'];
for (const [name, tokens] of Object.entries(table)) lines.push(`| ${name} | ${tokens} | 0% |`);
process.stdout.write(lines.join('\n') + '\n');
EOF
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT*)
    FAKE="$FAKEDIR/fake-claude.cmd"
    printf '@node "%%~dp0fake-claude.js" %%*\r\n' >"$FAKE"
    ;;
  *)
    FAKE="$FAKEDIR/fake-claude"
    printf '#!/usr/bin/env node\n' >"$FAKE"
    cat "$FAKEDIR/fake-claude.js" >>"$FAKE"
    chmod +x "$FAKE"
    ;;
esac

# The bug (#3197): the combined deny empties the deferred bucket out of the
# snapshot, its delta is null, and the verifier must publish the record as
# incomparable with a null combinedSaved — never a coerced 0.
avanish="$WORK/attr-vanish.json"
if (cd "$WORK" && FAKE_MODE=vanish node "$ENGINE" attribute --tools AlphaTool,BetaTool --verify-additivity --binary "$FAKE" --out "$avanish" >/dev/null); then
  assert_eq "$(jsonget "$avanish" 'j.perTool.find((t)=>t.tool==="AlphaTool").savedTokens')" "1400" \
    "per-tool rows with both buckets present still measure" "AlphaTool row wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.sumOfParts')" "2100" \
    "sum of parts is the sum of the savers" "sumOfParts wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.combinedSaved')" "null" \
    "vanished bucket yields combinedSaved null, never a coerced 0" "combinedSaved fabricated from a null delta"
  assert_eq "$(jsonget "$avanish" 'j.additivity.comparable')" "false" \
    "vanished bucket marks the additivity record incomparable" "additivity published comparable despite a vanished bucket"
  assert_eq "$(jsonget "$avanish" 'j.additivity.additive')" "false" \
    "incomparable additivity is never reported additive" "additive true despite a vanished bucket"
  if [[ "$(jsonget "$avanish" 'j.additivity.reasons.join(" ")')" == *"System tools (deferred)"* ]]; then
    ok "additivity record names the vanished bucket in its reasons"
  else
    fail "vanished-bucket reason missing from additivity record"
  fi
else
  fail "attribute --verify-additivity (vanish scenario) exited nonzero"
fi

# Control: all buckets present in every run — the verdict must be untouched.
actl="$WORK/attr-control.json"
if (cd "$WORK" && FAKE_MODE=control node "$ENGINE" attribute --tools AlphaTool,BetaTool --verify-additivity --binary "$FAKE" --out "$actl" >/dev/null); then
  assert_eq "$(jsonget "$actl" 'j.additivity.combinedSaved')" "2100" \
    "normal additivity case still measures the combined saving" "control combinedSaved wrong"
  assert_eq "$(jsonget "$actl" 'j.additivity.additive')" "true" \
    "normal additivity case still verifies additive" "control additive wrong"
  assert_eq "$(jsonget "$actl" 'j.additivity.comparable')" "true" \
    "normal additivity case stays comparable" "control comparable wrong"
  assert_eq "$(jsonget "$actl" 'j.knownUncovered.tools.includes("Artifact")')" "true" \
    "full-sweep-shaped attribute lists Artifact as known-uncovered" "Artifact omitted from knownUncovered"
  assert_eq "$(jsonget "$actl" 'j.knownUncovered.tools.includes("AskUserQuestion")')" "true" \
    "AskUserQuestion is known-uncovered, not silent" "AskUserQuestion omitted from knownUncovered"
  assert_eq "$(jsonget "$actl" 'j.knownUncovered.tools.includes("SendUserFile")')" "true" \
    "SendUserFile is known-uncovered, not silent" "SendUserFile omitted from knownUncovered"
  assert_eq "$(jsonget "$actl" 'j.knownUncovered.tools.includes("EnterPlanMode")')" "true" \
    "plan-mode EnterPlanMode is known-uncovered" "EnterPlanMode omitted from knownUncovered"
  assert_eq "$(jsonget "$actl" 'JSON.stringify(j.knownUncovered.notes).includes("MCP")')" "true" \
    "interactive-only MCP servers are noted as a class" "MCP class note missing"
else
  fail "attribute --verify-additivity (control scenario) exited nonzero"
fi

# A product interactive-only name that WAS a candidate this run is not
# repeated as known-uncovered — it is measured (or unmeasured-but-candidate).
aart="$WORK/attr-artifact-candidate.json"
if (cd "$WORK" && FAKE_MODE=control node "$ENGINE" attribute --tools Artifact --binary "$FAKE" --out "$aart" >/dev/null); then
  assert_eq "$(jsonget "$aart" 'j.knownUncovered.tools.includes("Artifact")')" "false" \
    "a candidate Artifact is not also listed as known-uncovered" "Artifact listed as both candidate and known-uncovered"
  assert_eq "$(jsonget "$aart" 'j.perTool.some((t)=>t.tool==="Artifact")')" "true" \
    "explicit Artifact stays a per-tool candidate" "explicit Artifact missing from perTool"
else
  fail "attribute --tools Artifact exited nonzero"
fi

# A single deny that empties a bucket poisons that per-tool row the same way.
agamma="$WORK/attr-gamma.json"
if (cd "$WORK" && FAKE_MODE=control node "$ENGINE" attribute --tools AlphaTool,GammaTool --verify-additivity --binary "$FAKE" --out "$agamma" >/dev/null); then
  assert_eq "$(jsonget "$agamma" 'j.perTool.find((t)=>t.tool==="GammaTool").savedTokens')" "null" \
    "per-tool row with a vanished bucket reports savedTokens null" "per-tool savedTokens fabricated from a null delta"
  assert_eq "$(jsonget "$agamma" 'j.perTool.find((t)=>t.tool==="GammaTool").comparable')" "false" \
    "per-tool row with a vanished bucket is incomparable" "per-tool row comparable despite a vanished bucket"
  assert_eq "$(jsonget "$agamma" 'j.additivity')" "null" \
    "a lone comparable saver runs no additivity check" "additivity ran with fewer than two savers"
else
  fail "attribute (gamma scenario) exited nonzero"
fi

# A bucket absent from BOTH runs is outside the binary's category vocabulary —
# a non-event, not a missing measurement.
anv="$WORK/attr-novocab.json"
if (cd "$WORK" && FAKE_MODE=novocab node "$ENGINE" attribute --tools AlphaTool,BetaTool --verify-additivity --binary "$FAKE" --out "$anv" >/dev/null); then
  assert_eq "$(jsonget "$anv" 'j.perTool.find((t)=>t.tool==="AlphaTool").savedTokens')" "1000" \
    "bucket absent from both runs still measures the present bucket" "vocabulary-absent bucket broke the per-tool row"
  assert_eq "$(jsonget "$anv" 'j.perTool.find((t)=>t.tool==="AlphaTool").comparable')" "true" \
    "bucket absent from both runs keeps the row comparable" "vocabulary-absent bucket poisoned comparability"
  assert_eq "$(jsonget "$anv" 'j.additivity.combinedSaved')" "1600" \
    "additivity over the present bucket alone still measures" "vocabulary-absent combinedSaved wrong"
  assert_eq "$(jsonget "$anv" 'j.additivity.additive')" "true" \
    "additivity over the present bucket alone still verifies" "vocabulary-absent additive wrong"
else
  fail "attribute (novocab scenario) exited nonzero"
fi

# --- verify-catalogue: binary existence, never invents presence -----------
# A tiny catalogue plus a byte file standing in for the binary: one row's
# keys are in the file, one row's key is not, one row has nothing to grep.
# The engine must report present/absent from the bytes, not from the
# catalogue's own claims.

minicat="$WORK/mini-levers.json"
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  schema: "context-budget.levers/1",
  meta: { categories: { "removes-weight": "x" }, verifiedAgainst: { cliVersion: "9.9.9", date: "2026-01-01" } },
  levers: [
    {
      id: "has-key",
      title: "disableWorkflows / CLAUDE_CODE_DISABLE_WORKFLOWS",
      category: "removes-weight", categoryBasis: "t", posture: "recommendable-on-fit",
      detection: "x", measurement: "x",
      emittedConfig: "{\"disableWorkflows\": true}",
      citations: ["https://example.com"], verified: "2026-01-01", recheckTrigger: "x",
    },
    {
      id: "missing-key",
      title: "notInThisBinaryKey",
      category: "removes-weight", categoryBasis: "t", posture: "recommendable-on-fit",
      detection: "x", measurement: "x",
      emittedConfig: "{\"notInThisBinaryKey\": true}",
      citations: ["https://example.com"], verified: "2026-01-01", recheckTrigger: "x",
    },
    {
      id: "no-tokens",
      title: "No extractable identifier here",
      category: "removes-weight", categoryBasis: "t", posture: "recommendable-on-fit",
      detection: "x", measurement: "x", emittedConfig: null,
      citations: ["https://example.com"], verified: "2026-01-01", recheckTrigger: "x",
    },
    {
      id: "detection-only",
      title: "No camel here",
      category: "removes-weight", categoryBasis: "t", posture: "recommendable-on-fit",
      detection: "enabledMcpjsonServers across scopes", measurement: "x",
      emittedConfig: null,
      citations: ["https://example.com"], verified: "2026-01-01", recheckTrigger: "x",
    },
  ],
}));
' "$minicat"
printf 'padding disableWorkflows CLAUDE_CODE_DISABLE_WORKFLOWS disableWorkflows padding' >"$WORK/fake-strings-bin"

vcat="$WORK/verify-cat.json"
if node "$ENGINE" verify-catalogue --binary "$WORK/fake-strings-bin" --catalogue "$minicat" --out "$vcat" >/dev/null; then
  assert_eq "$(jsonget "$vcat" 'j.schema')" "context-budget.catalogue-verify/1" \
    "verify-catalogue emits the catalogue-verify schema" "verify-catalogue schema wrong"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="has-key").tokens.find((t)=>t.name==="disableWorkflows").present')" "true" \
    "present key is reported present" "present key marked absent"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="has-key").tokens.find((t)=>t.name==="disableWorkflows").hits')" "2" \
    "hit count matches the binary occurrences" "hit count wrong"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="has-key").tokens.find((t)=>t.name==="CLAUDE_CODE_DISABLE_WORKFLOWS").present')" "true" \
    "present env name is reported present" "present env name marked absent"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="missing-key").tokens.find((t)=>t.name==="notInThisBinaryKey").present')" "false" \
    "absent key is reported absent (never invented present)" "absent key marked present"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="no-tokens").skipped')" "true" \
    "a row with no extractable key is skipped" "no-token row not skipped"
  assert_eq "$(jsonget "$vcat" 'j.missing')" "2" \
    "missing count includes detection-only absent key" "missing count wrong"
  assert_eq "$(jsonget "$vcat" 'j.rows.find((r)=>r.id==="detection-only").tokens.find((t)=>t.name==="enabledMcpjsonServers").present')" "false" \
    "camelCase in detection is extracted (not silently skipped)" "detection-only key not extracted"
else
  fail "verify-catalogue exited nonzero on a readable fake binary"
fi

# ReDoS-shaped title (long same-case run then _) must finish, not hang.
redoscat="$WORK/redos-levers.json"
node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  schema: "context-budget.levers/1",
  meta: { categories: { "removes-weight": "x" } },
  levers: [{
    id: "redos",
    title: "a" + "A".repeat(80) + "_",
    category: "removes-weight", categoryBasis: "t", posture: "recommendable-on-fit",
    detection: "x", measurement: "x", emittedConfig: null,
    citations: ["https://example.com"], verified: "2026-01-01", recheckTrigger: "x",
  }],
}));
' "$redoscat"
if node -e '
const { spawnSync } = require("child_process");
const r = spawnSync(process.execPath, [process.argv[1], "verify-catalogue", "--binary", process.argv[2], "--catalogue", process.argv[3]], { timeout: 2000, stdio: "ignore" });
process.exit(r.error ? 1 : (r.status ?? 1));
' "$ENGINE" "$WORK/fake-strings-bin" "$redoscat"; then
  ok "camelCase extract finishes on a ReDoS-shaped title (no hang)"
else
  fail "camelCase extract hung or failed on a ReDoS-shaped title"
fi

# A .cmd path with a sibling .exe scans the exe, not the wrapper.
printf 'wrapper-only no-keys-here' >"$WORK/shim-claude.cmd"
printf 'payload disableWorkflows CLAUDE_CODE_DISABLE_WORKFLOWS' >"$WORK/shim-claude.exe"
shimout="$WORK/verify-shim.json"
if node "$ENGINE" verify-catalogue --binary "$WORK/shim-claude.cmd" --catalogue "$minicat" --out "$shimout" >/dev/null; then
  assert_eq "$(jsonget "$shimout" 'j.rows.find((r)=>r.id==="has-key").tokens.find((t)=>t.name==="disableWorkflows").present')" "true" \
    "Windows .cmd with sibling .exe scans the exe" "shim scan missed the sibling exe payload"
else
  fail "verify-catalogue on a .cmd shim exited nonzero"
fi

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
