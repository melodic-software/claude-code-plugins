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
# coerced zero; per-bucket verdicts; an unmeasured verdict distinct from a
# measured negative), and verify-catalogue (binary-scan present/absent, never
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
# assert_exit <expected-code> <ok-message> <fail-message> <cmd...> — runs the
# command with both streams discarded and checks its exit code
assert_exit() {
  local want="$1" okmsg="$2" failmsg="$3"
  shift 3
  "$@" >/dev/null 2>&1
  local rc=$?
  if [[ $rc -eq "$want" ]]; then
    ok "$okmsg"
  else
    fail "$failmsg (exit $rc)"
  fi
}
# assert_degrade <out-file> <needle> <ok-message> <fail-message> <cmd...> — the
# command must exit 3 and leave a record naming the needle on stdout
assert_degrade() {
  local out="$1" needle="$2" okmsg="$3" failmsg="$4"
  shift 4
  "$@" >"$out" 2>/dev/null
  local rc=$?
  if [[ $rc -eq 3 ]] && grep -q "$needle" "$out"; then
    ok "$okmsg"
  else
    fail "$failmsg, got exit $rc"
  fi
}

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required to test the engine" >&2
  exit 1
fi

WORK="$(mktemp -d)"
# Git Bash hands node a POSIX /tmp path inside JS source strings unconverted;
# a mixed-form path reads on both sides.
if command -v cygpath >/dev/null 2>&1; then WORK="$(cygpath -m "$WORK")"; fi
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# jsonget <file> <js-expression over parsed `j`> — prints the value
jsonget() {
  node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const v=(function(){return eval(process.argv[2])})();process.stdout.write(String(v))" "$1" "$2"
}

# jsonmutate <in-file> <out-file> <js-statement over parsed `j`> — writes the
# mutated record to the out file
jsonmutate() {
  node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));eval(process.argv[3]);fs.writeFileSync(process.argv[2],JSON.stringify(j));" "$1" "$2" "$3"
}

# write_snapshot <file> <mode> <version> <signature> <systemtools> <skilltokens>
# Minimal but schema-valid snapshot record for compare tests. The deferred
# bucket is the literal 1000 in every record, which is why two of them compare
# with a deferred delta of 0 (the dA/dB test below).
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
assert_degrade "$WORK/garbage-out.json" 'context-budget.error/1' \
  "unrecognized format exits 3 with a structured error (never a guessed number)" \
  "unrecognized format: expected exit 3 + error record" \
  node "$ENGINE" parse-context --file "$WORK/garbage.md"

# A category table that parses but lacks the System tools row must also refuse.
printf '## Context Usage\n\n### Estimated usage by category\n\n| Category | Tokens | Percentage |\n|---|---|---|\n| Something else | 1.0k | 1.0%% |\n' >"$WORK/norow.md"
assert_degrade "$WORK/norow-out.json" 'System tools' \
  "missing System tools row refuses rather than guessing" \
  "missing System tools row: expected exit 3 naming the row" \
  node "$ENGINE" parse-context --file "$WORK/norow.md"

# --- parse-context: one system-tool bucket alone parses --------------------

# Deferred-only shape (observed on headless Claude Code 2.1.289). Expected
# values come from the fixture's own cells: 14k deferred, 2.5k system prompt.
donly="$WORK/deferred-only.json"
if node "$ENGINE" parse-context --file "$SCRIPT_DIR/fixtures/context-deferred-only.md" --out "$donly" >/dev/null; then
  ok "deferred-only table exits 0"
  assert_eq "$(jsonget "$donly" '"System tools" in j.categories')" "false" \
    "absent System tools row stays absent (unmeasured, not zero-filled)" "absent System tools row was filled in"
  assert_eq "$(jsonget "$donly" 'j.categories["System tools (deferred)"]')" "14000" \
    "deferred row 14k parses to 14000" "deferred row misparsed"
  assert_eq "$(jsonget "$donly" 'j.categories["System prompt"]')" "2500" \
    "other categories still parse alongside a missing bucket" "other categories lost"
  assert_eq "$(jsonget "$donly" 'Object.keys(j.categories).length')" "7" \
    "every category row in the fixture is reported" "category count wrong"
  assert_eq "$(jsonget "$donly" 'j.caveats.some((c)=>c.includes("\"System tools\" row absent") && c.includes("unmeasured"))')" "true" \
    "a caveat names the missing System tools row" "missing-row caveat absent"
else
  fail "deferred-only table did not parse"
fi

# Prefix-only shape: the deferred row is the absent one.
printf '## Context Usage\n\n### Estimated usage by category\n\n| Category | Tokens | Percentage |\n|---|---|---|\n| System tools | 3.0k | 1.0%% |\n| Messages | 10 | 0.0%% |\n' >"$WORK/prefix-only.md"
ponly="$WORK/prefix-only.json"
if node "$ENGINE" parse-context --file "$WORK/prefix-only.md" --out "$ponly" >/dev/null; then
  assert_eq "$(jsonget "$ponly" 'j.categories["System tools"]')" "3000" \
    "prefix-only table parses its System tools row" "prefix-only System tools misparsed"
  assert_eq "$(jsonget "$ponly" '"System tools (deferred)" in j.categories')" "false" \
    "absent deferred row stays absent" "absent deferred row was filled in"
  assert_eq "$(jsonget "$ponly" 'j.caveats.some((c)=>c.includes("\"System tools (deferred)\" row absent"))')" "true" \
    "a caveat names the missing deferred row" "missing deferred-row caveat absent"
else
  fail "prefix-only table did not parse"
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
assert_eq "$(jsonget "$row2" 'j.comparability.modeBinaryComparable')" "true" \
  "same-signature runs keep the shared mode/binary predicate" "same-signature runs lost modeBinaryComparable"

# --- compare: signature mismatch poisons the System tools delta -----------

row3="$WORK/row-sig.json"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/c.json" --out "$row3" >/dev/null
assert_eq "$(jsonget "$row3" 'j.comparability.systemToolsComparable')" "false" \
  "skill-listing signature mismatch marks System tools incomparable" "signature mismatch not detected"
assert_eq "$(jsonget "$row3" 'j.comparability.modeBinaryComparable')" "true" \
  "skill-listing signature mismatch does not poison the shared mode/binary predicate" \
  "signature mismatch wrongly flipped modeBinaryComparable"
if grep -q 'skill listing differs' "$row3"; then
  ok "signature mismatch carries its reason in the row"
else
  fail "signature-mismatch reason missing"
fi

# --- compare: every recorded mismatch poisons the predicate ---------------

jsonmutate "$WORK/a.json" "$WORK/d.json" "j.binary.path='/opt/other/claude'"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/d.json" --out "$WORK/row-path.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-path.json" 'j.comparability.systemToolsComparable')" "false" \
  "same version but different binary path marks System tools incomparable" \
  "binary-path mismatch not reflected in the predicate"
assert_eq "$(jsonget "$WORK/row-path.json" 'j.comparability.modeBinaryComparable')" "false" \
  "binary-path mismatch also flips the shared mode/binary predicate" \
  "binary-path mismatch not reflected in modeBinaryComparable"

jsonmutate "$WORK/a.json" "$WORK/e.json" "j.skillListing.tokens=2500"
node "$ENGINE" compare --before "$WORK/a.json" --after "$WORK/e.json" --out "$WORK/row-skills.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-skills.json" 'j.comparability.systemToolsComparable')" "false" \
  "matching listing but moved Skills bucket marks System tools incomparable" \
  "skills-bucket drift not reflected in the predicate"
assert_eq "$(jsonget "$WORK/row-skills.json" 'j.comparability.modeBinaryComparable')" "true" \
  "Skills-token drift does not poison the shared mode/binary predicate" \
  "Skills-token drift wrongly flipped modeBinaryComparable"

# --- compare: a bucket missing from a cli-parse snapshot -------------------

jsonmutate "$WORK/a.json" "$WORK/dA.json" 'delete j.categories["System tools"]'
jsonmutate "$WORK/b.json" "$WORK/dB.json" 'delete j.categories["System tools"]'
node "$ENGINE" compare --before "$WORK/dA.json" --after "$WORK/dB.json" --out "$WORK/row-donly.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-donly.json" '"System tools" in j.delta')" "false" \
  "two deferred-only snapshots yield no System tools delta row" "System tools delta invented for two deferred-only runs"
assert_eq "$(jsonget "$WORK/row-donly.json" 'j.delta["System tools (deferred)"]')" "0" \
  "the measured deferred bucket still compares" "deferred delta lost between deferred-only runs"
node "$ENGINE" compare --before "$WORK/dA.json" --after "$WORK/b.json" --out "$WORK/row-mixed.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-mixed.json" 'j.delta["System tools"]')" "null" \
  "deferred-only vs full snapshot yields a null System tools delta, never 0" "one-sided System tools delta not null"
if [[ "$(jsonget "$WORK/row-mixed.json" 'j.unmeasured["System tools"]')" == *"only one run"* ]]; then
  ok "the null System tools delta carries a reason"
else
  fail "null System tools delta has no reason"
fi
assert_eq "$(jsonget "$WORK/row-self.json" 'Object.keys(j.unmeasured).length')" "0" \
  "fully measured runs carry no unmeasured reasons" "unmeasured reasons on a fully measured compare"

# --- emit: --out creates missing parent directories -----------------------

deepout="$WORK/fresh/data/dir/parsed.json"
if node "$ENGINE" parse-context --file "$FIXTURE" --out "$deepout" >/dev/null && [[ -f "$deepout" ]]; then
  ok "--out creates its parent directories (fresh data dir does not ENOENT)"
else
  fail "--out into a nonexistent directory failed"
fi

# --- compare: schema validation -------------------------------------------

printf '{"schema":"something-else/9"}\n' >"$WORK/notsnap.json"
assert_exit 2 "compare rejects a non-snapshot input as a usage error" \
  "compare accepted a non-snapshot input" \
  node "$ENGINE" compare --before "$WORK/notsnap.json" --after "$WORK/a.json"

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

assert_exit 2 "ledger rejects a non-ledger row (snapshots are not ledger rows)" \
  "ledger accepted a snapshot as a row" \
  node "$ENGINE" ledger --append "$WORK/a.json" --dir "$LDIR"

assert_exit 2 "ledger rejects a relative --dir" \
  "ledger accepted a relative --dir" \
  node "$ENGINE" ledger --append "$row" --dir "relative/dir"

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
// nonadd — the measured shape the audit found: the prefix side double-counts
// (combined saves 400 less than the sum of parts) while the deferred side
// sums to the token. Every bucket is present in every run, so the reading is
// comparable and the negative verdict is measured, not unmeasured.
if (mode === 'nonadd') prefixSaved['AlphaTool+BetaTool'] = 1200;
// saturate — combined prefix numbers would add, but the run is marked a
// synthesized zero. The verdict must be unmeasured, not the true the
// arithmetic would publish.
// noprefix: the observed headless shape with no prefix System tools row.
const table = {};
if (mode !== 'noprefix') table['System tools'] = 18000 - (prefixSaved[key] ?? 0);
// The deferred bucket is dropped (omitted, not reported as 0) when:
//   novocab      — this fake "version" has no deferred bucket in any run;
//   vanish       — the combined deny empties it out of the snapshot (#3197);
//   GammaTool    — a single deny empties it out of the snapshot.
const dropDeferred = mode === 'novocab'
  || (mode === 'vanish' && key === 'AlphaTool+BetaTool')
  || key === 'GammaTool';
if (!dropDeferred) table['System tools (deferred)'] = 12000 - (deferredSaved[key] ?? 0);
table.Messages = 42;
// skilltok — combined run only: Skills-token count moves while the listing
// signature stays identical, so systemToolsComparable is false and the
// shared mode/binary predicate stays true.
if (mode === 'skilltok') table.Skills = key === 'AlphaTool+BetaTool' ? 2500 : 2000;
const lines = ['## Context Usage', '', '**Model:** fake-model', '',
  '### Estimated usage by category', '',
  '| Category | Tokens | Percentage |', '|---|---|---|'];
for (const [name, tokens] of Object.entries(table)) lines.push(`| ${name} | ${tokens} | 0% |`);
// skillsig — combined run only: a Skills table appears, changing the listing
// signature. Per-tool runs stay matching so they remain savers.
if (mode === 'skillsig' && key === 'AlphaTool+BetaTool') {
  lines.push('', '### Skills', '', '| Skill | Source | Tokens |', '|---|---|---|',
    '| drift-skill | User | 100 |');
}
// A deny run can raise a disclosure the baseline does not. The attribution
// record must keep it (#3356 H3).
if (mode === 'saturate' && key === 'AlphaTool+BetaTool') {
  lines.push('', '<!-- synthesized-zero: System tools -->');
}
if (key) lines.push('', `Caveat: deny-run disclosure for ${key}`);
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

# attr <fake-mode> <out-file> <attribute-args...> — one hermetic attribute run
# against the fake binary, from $WORK so the engine stays in cli-parse mode.
attr() {
  local mode="$1" out="$2"
  shift 2
  (cd "$WORK" && FAKE_MODE="$mode" node "$ENGINE" attribute "$@" --binary "$FAKE" --out "$out" >/dev/null)
}

# The bug (#3197): the combined deny empties the deferred bucket out of the
# snapshot, its delta is null, and the verifier must publish the record as
# incomparable with a null combinedSaved — never a coerced 0.
avanish="$WORK/attr-vanish.json"
if attr vanish "$avanish" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$avanish" 'j.perTool.find((t)=>t.tool==="AlphaTool").savedTokens')" "1400" \
    "per-tool rows with both buckets present still measure" "AlphaTool row wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.sumOfParts')" "2100" \
    "sum of parts is the sum of the savers" "sumOfParts wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.combinedSaved')" "null" \
    "vanished bucket yields combinedSaved null, never a coerced 0" "combinedSaved fabricated from a null delta"
  assert_eq "$(jsonget "$avanish" 'j.additivity.comparable')" "false" \
    "vanished bucket marks the additivity record incomparable" "additivity published comparable despite a vanished bucket"
  assert_eq "$(jsonget "$avanish" 'j.additivity.additive')" "null" \
    "an unmeasurable additivity reading reports a null verdict, not a definite negative" \
    "unmeasured additivity published as a boolean verdict"
  if [[ "$(jsonget "$avanish" 'j.additivity.reasons.join(" ")')" == *"System tools (deferred)"* ]]; then
    ok "additivity record names the vanished bucket in its reasons"
  else
    fail "vanished-bucket reason missing from additivity record"
  fi
  # Per bucket: the vanished deferred side is unmeasured, but the prefix side
  # was measured in both runs and still gets a verdict.
  assert_eq "$(jsonget "$avanish" 'j.additivity.perBucket["System tools"].sumOfParts')" "1600" \
    "per-bucket sum of parts comes off the per-tool prefixDelta values" "per-bucket prefix sumOfParts wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.perBucket["System tools"].combinedSaved')" "1600" \
    "per-bucket combined saving comes off the combined run's prefix delta" "per-bucket prefix combinedSaved wrong"
  assert_eq "$(jsonget "$avanish" 'j.additivity.perBucket["System tools"].additive')" "true" \
    "a vanished deferred bucket does not poison the prefix bucket's verdict" "prefix verdict lost to an unrelated vanish"
  assert_eq "$(jsonget "$avanish" 'j.additivity.perBucket["System tools (deferred)"].combinedSaved')" "null" \
    "the vanished bucket's combined saving stays null" "vanished per-bucket saving coerced to a number"
  assert_eq "$(jsonget "$avanish" 'j.additivity.perBucket["System tools (deferred)"].additive')" "null" \
    "the vanished bucket's verdict is unmeasured, not a negative" "vanished per-bucket verdict published as a boolean"
else
  fail "attribute --verify-additivity (vanish scenario) exited nonzero"
fi

# A measured negative: every bucket present in every run, the reading
# comparable, and the prefix side genuinely failing to add. The unmeasured
# verdict above must NOT be the same value as this one.
anon="$WORK/attr-nonadditive.json"
if attr nonadd "$anon" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$anon" 'j.additivity.comparable')" "true" \
    "the measured-negative reading is comparable" "nonadd reading marked incomparable"
  assert_eq "$(jsonget "$anon" 'j.additivity.additive')" "false" \
    "a comparable reading whose parts overshoot reports a measured false" "nonadd verdict wrong"
  assert_eq "$(jsonget "$anon" 'j.additivity.additive === JSON.parse(require("fs").readFileSync("'"$avanish"'","utf8")).additivity.additive')" "false" \
    "the unmeasured verdict is a different value from the measured negative" \
    "unmeasured and measured-negative additivity verdicts are indistinguishable"
  assert_eq "$(jsonget "$anon" 'j.additivity.perBucket["System tools"].additive')" "false" \
    "the prefix bucket reports its own measured negative" "per-bucket prefix verdict wrong under nonadd"
  assert_eq "$(jsonget "$anon" 'j.additivity.perBucket["System tools"].combinedSaved')" "1200" \
    "the prefix bucket's combined saving is the combined run's own number" "per-bucket prefix combinedSaved wrong under nonadd"
  assert_eq "$(jsonget "$anon" 'j.additivity.perBucket["System tools (deferred)"].additive')" "true" \
    "the deferred bucket adds even when the prefix bucket does not" "per-bucket deferred verdict wrong under nonadd"
else
  fail "attribute --verify-additivity (nonadd scenario) exited nonzero"
fi

# Control: all buckets present in every run — the verdict must be untouched.
actl="$WORK/attr-control.json"
if attr control "$actl" --tools AlphaTool,BetaTool --verify-additivity; then
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
  assert_eq "$(jsonget "$actl" 'j.caveats.filter((c)=>c.startsWith("cli-parse mode")).length')" "1" \
    "shared cli-parse caveat is kept once" "baseline caveat duplicated or dropped"
  assert_eq "$(jsonget "$actl" 'j.caveats.includes("deny-run disclosure for AlphaTool")')" "true" \
    "a per-tool deny run's caveat reaches the attribution record" "deny-run caveat discarded"
  assert_eq "$(jsonget "$actl" 'j.caveats.includes("deny-run disclosure for AlphaTool+BetaTool")')" "true" \
    "the combined deny run's caveat reaches the attribution record" "combined-run caveat discarded"
  assert_eq "$(jsonget "$actl" 'j.knownUncovered.tools.includes("EndConversation")')" "true" \
    "EndConversation is known-uncovered in a headless sweep" "EndConversation omitted from knownUncovered"
  assert_eq "$(jsonget "$actl" 'JSON.stringify(j.knownUncovered.deniedAbsent)')" "[]" \
    "no operator deny leaves deniedAbsent empty" "deniedAbsent populated without --operator-deny"
else
  fail "attribute --verify-additivity (control scenario) exited nonzero"
fi

adeny="$WORK/attr-operator-deny.json"
if attr control "$adeny" --tools AlphaTool,BetaTool --operator-deny AskUserQuestion,EnterPlanMode; then
  assert_eq "$(jsonget "$adeny" 'j.knownUncovered.tools.includes("AskUserQuestion")')" "false" \
    "an operator-denied interactive tool is not labeled structurally unreachable" \
    "AskUserQuestion stayed in knownUncovered.tools under --operator-deny"
  assert_eq "$(jsonget "$adeny" 'j.knownUncovered.deniedAbsent.includes("AskUserQuestion")')" "true" \
    "operator-denied AskUserQuestion is recorded as deniedAbsent" "AskUserQuestion missing from deniedAbsent"
  assert_eq "$(jsonget "$adeny" 'j.knownUncovered.deniedAbsent.includes("EnterPlanMode")')" "true" \
    "operator-denied EnterPlanMode is recorded as deniedAbsent" "EnterPlanMode missing from deniedAbsent"
  assert_eq "$(jsonget "$adeny" 'j.knownUncovered.tools.includes("Artifact")')" "true" \
    "an interactive tool the operator did not deny stays known-uncovered" "Artifact dropped without a deny"
else
  fail "attribute --operator-deny exited nonzero"
fi

# Synthesized zero: the combined prefix arithmetic adds, and the guard must
# still refuse a verdict.
asat="$WORK/attr-saturate.json"
if attr saturate "$asat" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$asat" 'j.additivity.additive')" "null" \
    "a synthesized zero publishes no summed additivity verdict" "saturated additivity published a boolean"
  assert_eq "$(jsonget "$asat" 'j.additivity.comparable')" "false" \
    "a synthesized zero marks the summed record unmeasured" "saturated additivity stayed comparable"
  assert_eq "$(jsonget "$asat" 'j.additivity.perBucket["System tools"].additive')" "null" \
    "the synthesized prefix bucket has no verdict" "saturated prefix verdict published a boolean"
  assert_eq "$(jsonget "$asat" 'j.additivity.perBucket["System tools (deferred)"].additive')" "true" \
    "a real deferred bucket still gets its verdict" "saturated run dropped the deferred verdict"
  if [[ "$(jsonget "$asat" 'j.additivity.reasons.join(" ")')" == *"synthesized zero"* ]]; then
    ok "additivity record names the synthesized zero"
  else
    fail "synthesized-zero reason missing from additivity record"
  fi
else
  fail "attribute --verify-additivity (saturate scenario) exited nonzero"
fi

# A product interactive-only name that WAS a candidate this run is not
# repeated as known-uncovered — it is measured (or unmeasured-but-candidate).
aart="$WORK/attr-artifact-candidate.json"
if attr control "$aart" --tools Artifact; then
  assert_eq "$(jsonget "$aart" 'j.knownUncovered.tools.includes("Artifact")')" "false" \
    "a candidate Artifact is not also listed as known-uncovered" "Artifact listed as both candidate and known-uncovered"
  assert_eq "$(jsonget "$aart" 'j.perTool.some((t)=>t.tool==="Artifact")')" "true" \
    "explicit Artifact stays a per-tool candidate" "explicit Artifact missing from perTool"
else
  fail "attribute --tools Artifact exited nonzero"
fi

# A single deny that empties a bucket poisons that per-tool row the same way.
agamma="$WORK/attr-gamma.json"
if attr control "$agamma" --tools AlphaTool,GammaTool --verify-additivity; then
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
if attr novocab "$anv" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$anv" 'j.perTool.find((t)=>t.tool==="AlphaTool").savedTokens')" "1000" \
    "bucket absent from both runs still measures the present bucket" "vocabulary-absent bucket broke the per-tool row"
  assert_eq "$(jsonget "$anv" 'j.perTool.find((t)=>t.tool==="AlphaTool").comparable')" "true" \
    "bucket absent from both runs keeps the row comparable" "vocabulary-absent bucket poisoned comparability"
  assert_eq "$(jsonget "$anv" 'j.additivity.combinedSaved')" "1600" \
    "additivity over the present bucket alone still measures" "vocabulary-absent combinedSaved wrong"
  assert_eq "$(jsonget "$anv" 'j.additivity.additive')" "true" \
    "additivity over the present bucket alone still verifies" "vocabulary-absent additive wrong"
  assert_eq "$(jsonget "$anv" 'Object.keys(j.additivity.perBucket).join(",")')" "System tools" \
    "a bucket absent from both runs gets no per-bucket verdict row" "vocabulary-absent bucket invented a per-bucket verdict"
else
  fail "attribute (novocab scenario) exited nonzero"
fi

# Prefix-only listing drift: the combined run's skill listing (or Skills-token
# count) changes, so systemToolsComparable is false, but the deferred bucket's
# numeric deltas remain valid under the shared mode/binary checks. Applying
# the prefix flag to every bucket would publish the deferred verdict as null.
askillsig="$WORK/attr-skillsig.json"
if attr skillsig "$askillsig" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$askillsig" 'j.additivity.comparable')" "false" \
    "combined listing drift marks the top-level additivity record incomparable" \
    "skillsig top-level comparable stayed true"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.additive')" "null" \
    "combined listing drift leaves the top-level verdict unmeasured" \
    "skillsig top-level additive published as a boolean"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools"].additive')" "null" \
    "listing drift leaves the prefix bucket verdict unmeasured" \
    "skillsig prefix verdict published as a boolean"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools"].sumOfParts')" "1600" \
    "listing drift still reports the prefix sum of parts" "skillsig prefix sumOfParts wrong"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools"].combinedSaved')" "1600" \
    "listing drift still reports the prefix combined saving" "skillsig prefix combinedSaved wrong"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools (deferred)"].additive')" "true" \
    "listing drift does not take the deferred bucket's measured verdict" \
    "skillsig deferred verdict lost to a prefix-only mismatch"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools (deferred)"].sumOfParts')" "500" \
    "listing drift still reports the deferred sum of parts" "skillsig deferred sumOfParts wrong"
  assert_eq "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools (deferred)"].combinedSaved')" "500" \
    "listing drift still reports the deferred combined saving" "skillsig deferred combinedSaved wrong"
  if [[ "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools"].reasons.join(" ")')" == *"skill listing"* ]]; then
    ok "prefix bucket names the listing mismatch in its reasons"
  else
    fail "skillsig prefix reasons missing the listing mismatch"
  fi
  if [[ "$(jsonget "$askillsig" 'j.additivity.perBucket["System tools (deferred)"].reasons.join(" ")')" == *"skill listing"* ]]; then
    fail "skillsig deferred reasons inherited a prefix-only listing mismatch"
  else
    ok "deferred bucket does not inherit prefix-only listing reasons"
  fi
else
  fail "attribute --verify-additivity (skillsig scenario) exited nonzero"
fi

askilltok="$WORK/attr-skilltok.json"
if attr skilltok "$askilltok" --tools AlphaTool,BetaTool --verify-additivity; then
  assert_eq "$(jsonget "$askilltok" 'j.additivity.comparable')" "false" \
    "combined Skills-token drift marks the top-level additivity record incomparable" \
    "skilltok top-level comparable stayed true"
  assert_eq "$(jsonget "$askilltok" 'j.additivity.perBucket["System tools"].additive')" "null" \
    "Skills-token drift leaves the prefix bucket verdict unmeasured" \
    "skilltok prefix verdict published as a boolean"
  assert_eq "$(jsonget "$askilltok" 'j.additivity.perBucket["System tools (deferred)"].additive')" "true" \
    "Skills-token drift does not take the deferred bucket's measured verdict" \
    "skilltok deferred verdict lost to a prefix-only mismatch"
else
  fail "attribute --verify-additivity (skilltok scenario) exited nonzero"
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
  assert_eq "$(jsonget "$vcat" 'Object.prototype.hasOwnProperty.call(j, "unstored")')" "false" \
    "verify-catalogue omits unstored unless --find-unstored" "unstored present without the flag"
else
  fail "verify-catalogue exited nonzero on a readable fake binary"
fi

printf 'padding CLAUDE_CODE_DISABLE_CRON CLAUDE_CODE_ENABLE_DESIGN_SYNC CLAUDE_CODE_DISABLE_WORKFLOWS' >"$WORK/fake-strings-bin"
vunstored="$WORK/verify-unstored.json"
if node "$ENGINE" verify-catalogue --find-unstored --binary "$WORK/fake-strings-bin" --catalogue "$minicat" --out "$vunstored" >/dev/null; then
  assert_eq "$(jsonget "$vunstored" 'j.unstored.includes("CLAUDE_CODE_DISABLE_CRON")')" "true" \
    "find-unstored reports an env name no row cites" "CLAUDE_CODE_DISABLE_CRON missing from unstored"
  assert_eq "$(jsonget "$vunstored" 'j.unstored.includes("CLAUDE_CODE_ENABLE_DESIGN_SYNC")')" "true" \
    "find-unstored reports the second uncited env name" "CLAUDE_CODE_ENABLE_DESIGN_SYNC missing from unstored"
  assert_eq "$(jsonget "$vunstored" 'j.unstored.includes("CLAUDE_CODE_DISABLE_WORKFLOWS")')" "false" \
    "find-unstored does not report an env name a row already cites" "cited env name listed as unstored"
else
  fail "verify-catalogue --find-unstored exited nonzero"
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

assert_degrade "$WORK/nobin.json" 'binary-not-found' \
  "snapshot with a missing --binary degrades with a structured error" \
  "missing --binary: expected exit 3 + binary-not-found" \
  node "$ENGINE" snapshot --binary "$WORK/does-not-exist"

# Headless /context with no prefix System tools row (the 2.1.289 shape) and no
# Agent SDK: snapshot must return a cli-parse record, not exit 3.
snapnp="$WORK/snap-noprefix.json"
if (cd "$WORK" && FAKE_MODE=noprefix node "$ENGINE" snapshot --binary "$FAKE" --out "$snapnp" >/dev/null); then
  assert_eq "$(jsonget "$snapnp" 'j.mode')" "cli-parse" \
    "snapshot without a System tools row returns a cli-parse record" "snapshot mode wrong"
  assert_eq "$(jsonget "$snapnp" '"System tools" in j.categories')" "false" \
    "snapshot leaves the absent System tools bucket out" "snapshot filled the absent System tools bucket"
  assert_eq "$(jsonget "$snapnp" 'j.caveats.some((c)=>c.includes("\"System tools\" row absent at 9.9.9"))')" "true" \
    "snapshot caveat names the missing row and the binary version" "snapshot caveat missing row or version"
else
  fail "snapshot exited nonzero on a table without a System tools row"
fi

# Two such snapshots compared: the prefix bucket is absent from both, but the
# parser disclosed it, so the ledger row must say it went unmeasured. Both
# runs print the same deferred cell (12000), so that delta is 0.
snapnp2="$WORK/snap-noprefix-2.json"
(cd "$WORK" && FAKE_MODE=noprefix node "$ENGINE" snapshot --binary "$FAKE" --out "$snapnp2" >/dev/null)
node "$ENGINE" compare --before "$snapnp" --after "$snapnp2" --out "$WORK/row-noprefix.json" >/dev/null
assert_eq "$(jsonget "$WORK/row-noprefix.json" '"System tools" in j.delta')" "false" \
  "disclosed-absent bucket gets no invented delta" "delta invented for a bucket absent from both runs"
assert_eq "$(jsonget "$WORK/row-noprefix.json" 'typeof j.unmeasured["System tools"]')" "string" \
  "disclosed-absent bucket is listed in unmeasured with a reason" "ledger hides the unmeasured System tools bucket"
assert_eq "$(jsonget "$WORK/row-noprefix.json" 'j.delta["System tools (deferred)"]')" "0" \
  "the measured deferred bucket still compares" "deferred delta wrong between noprefix runs"

# Attribution over the same shape: the deferred side moves by 400 (12000 vs
# 11600 with AlphaTool denied), but with the prefix bucket unmeasured the
# saving is null and the row incomparable, never 400 with the prefix as 0.
anp="$WORK/attr-noprefix.json"
if attr noprefix "$anp" --tools AlphaTool; then
  assert_eq "$(jsonget "$anp" 'j.perTool[0].deferredDelta')" "-400" \
    "deferred delta is still measured when the prefix bucket is absent" "deferred delta lost"
  assert_eq "$(jsonget "$anp" 'j.perTool[0].savedTokens')" "null" \
    "unmeasured prefix bucket makes savedTokens null, not the deferred side alone" \
    "unmeasured prefix bucket counted as zero in savedTokens"
  assert_eq "$(jsonget "$anp" 'j.perTool[0].comparable')" "false" \
    "unmeasured prefix bucket marks the row incomparable" "row with an unmeasured prefix bucket published comparable"
else
  fail "attribute (noprefix scenario) exited nonzero"
fi

# --- summary ---------------------------------------------------------------

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
