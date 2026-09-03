#!/usr/bin/env bash
# Self-test for scripts/run-plugin-tests.sh: the parallel runner, the serial
# allowlist, the print lock, the skip accounting, and the exit contract.
#
# Fixtures are throwaway suites under a mktemp root handed to the runner with
# --root, so the repository's own corpus is never discovered here. No git state
# is created (claude-code-plugins#2839).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/run-plugin-tests.sh"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# make_root <name> -> prints a fresh fixture root with the plugin/hook layout.
make_root() {
  local r="$scratch/$1"
  mkdir -p "$r/plugins" "$r/.claude/hooks"
  printf '%s' "$r"
}

# write_suite <root> <rel-path> <body> -> a suite script under the fixture root.
write_suite() {
  local path="$1/$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\n%s\n' "$3" >"$path"
}

# run_runner <expected-rc> <label> [runner args...]: runs the runner, records
# its combined output in RUN_OUTPUT and asserts the exit status.
run_runner() {
  local want_rc="$1" label="$2" rc=0
  shift 2
  RUN_OUTPUT="$(bash "$RUNNER" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want_rc" ]]; then
    ok "$label (rc=$rc)"
  else
    fail "$label: expected rc=$want_rc got rc=$rc; output: $RUN_OUTPUT"
  fi
}

assert_output_has() {
  local label="$1" needle="$2"
  if [[ "$RUN_OUTPUT" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label: expected output to contain '$needle'; got: $RUN_OUTPUT"
  fi
}

assert_output_lacks() {
  local label="$1" needle="$2"
  if [[ "$RUN_OUTPUT" != *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label: expected output NOT to contain '$needle'; got: $RUN_OUTPUT"
  fi
}

empty_list="$scratch/empty-serial.txt"
: >"$empty_list"

# --- exit contract -----------------------------------------------------------

r="$(make_root pass)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "ok: b"'
write_suite "$r" .claude/hooks/h.test.sh 'echo "ok: h"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "every suite passing exits 0" --root "$r"
assert_output_has "each suite is announced" "=== plugins/a/a.test.sh ==="
assert_output_has "repo-local hook suites are discovered" "PASS: .claude/hooks/h.test.sh"
assert_output_has "the all-green summary line" "All plugin tests passed."
assert_output_has "the suite count is reported" "Suites: 3 (0 serial, 3 across up to 1 job(s))"

r="$(make_root fail)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "FAIL: b broke" >&2; exit 1'
write_suite "$r" plugins/c/c.test.sh 'echo "ok: c"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "one failing suite exits 1" --root "$r"
assert_output_has "the failing suite is named" "FAIL: plugins/b/b.test.sh"
assert_output_has "suites after the failure still run" "PASS: plugins/c/c.test.sh"
assert_output_has "the failure summary line" "One or more plugin tests failed."

r="$(make_root skips)"
write_suite "$r" plugins/a/a.test.sh 'echo "SKIP: shfmt not installed"; echo "ok: rest"'
write_suite "$r" plugins/b/b.test.sh 'echo "ok: b"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "an optional SKIP still exits 0" --root "$r"
assert_output_has "the skipped suite is named with its reason" "SKIPPED: plugins/a/a.test.sh — 1 SKIP(s), first: shfmt not installed"
assert_output_has "the aggregate counts the skip" "Plugin test aggregate: 1 optional SKIP(s), 0 DISCRIMINATING SKIP(s)."
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "--strict-skips turns the optional SKIP into a failure" --root "$r" --strict-skips
assert_output_has "strict mode says why" "--strict-skips: 1 optional SKIP(s)"

r="$(make_root disc)"
write_suite "$r" plugins/a/a.test.sh 'echo "DISCRIMINATING SKIP: git too old"; echo "ok: rest"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a DISCRIMINATING SKIP fails the run" --root "$r"
assert_output_has "the vacated suite is named" "DISCRIMINATING SKIP: plugins/a/a.test.sh vacated 1 discriminating case(s)"

r="$(make_root none)"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "no suites at all is an error, not a pass" --root "$r"
assert_output_has "the empty corpus is named" "no plugin tests found"

r="$(make_root argv)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "--jobs 0 is rejected" --root "$r" --jobs 0
assert_output_has "the bad job count is named" "--jobs must be a positive integer (got '0')"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "an unknown flag prints usage" --root "$r" --parallel
assert_output_has "usage names the flags" "usage: run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR]"

# --- parallelism and the serial allowlist -------------------------------------
#
# Probe suites mark themselves running, pause, and record every OTHER marker
# they can see: an overlap file with content means the suite shared its window
# with another suite. Under --jobs 3 the three parallel probes must overlap;
# the serial probes must never see anyone.

r="$(make_root parallel)"
probe_dir="$scratch/probes"
mkdir -p "$probe_dir"
probe_body() {
  cat <<EOF
me="\${BASH_SOURCE[0]##*/}"
: >"$probe_dir/running.\$me"
sleep 0.6
for f in "$probe_dir"/running.*; do
  [[ "\$f" == *"running.\$me" ]] || echo "overlap: \${f##*/running.}" >>"$probe_dir/overlap.\$me"
done
rm -f "$probe_dir/running.\$me"
for i in \$(seq 1 200); do echo "tag-\$me line \$i"; done
echo "ok: \$me"
EOF
}
for name in p1 p2 p3 s1 s2; do
  write_suite "$r" "plugins/$name/$name.test.sh" "$(probe_body)"
done
serial_list="$scratch/serial.txt"
printf '# comment line\n\nplugins/s1/s1.test.sh # trailing comment\n  plugins/s2/s2.test.sh  \n' >"$serial_list"

PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "parallel run with a serial allowlist exits 0" --root "$r" --jobs 3
assert_output_has "the split is reported" "Suites: 5 (2 serial, 3 across up to 3 job(s))"
for name in s1 s2; do
  if [[ -s "$probe_dir/overlap.$name.test.sh" ]]; then
    fail "serial suite $name overlapped another suite: $(cat "$probe_dir/overlap.$name.test.sh")"
  else
    ok "serial suite $name never ran alongside another suite"
  fi
done
overlaps=0
for name in p1 p2 p3; do
  [[ -s "$probe_dir/overlap.$name.test.sh" ]] && overlaps=$((overlaps + 1))
done
if ((overlaps > 0)); then
  ok "the parallel group actually ran concurrently ($overlaps of 3 probes saw a sibling)"
else
  fail "no parallel probe saw a sibling under --jobs 3; the group ran serially"
fi
# Serial suites run first, so every serial block precedes every parallel one.
serial_last="$(grep -n '^PASS: plugins/s' <<<"$RUN_OUTPUT" | tail -n 1 | cut -d: -f1)"
parallel_first="$(grep -n '^PASS: plugins/p' <<<"$RUN_OUTPUT" | head -n 1 | cut -d: -f1)"
if [[ -n "$serial_last" && -n "$parallel_first" ]] && ((serial_last < parallel_first)); then
  ok "serial suites finish before the parallel group starts"
else
  fail "serial suites did not all finish before the parallel group (serial last line $serial_last, parallel first line $parallel_first)"
fi
# Each suite's block is contiguous: between its header and its PASS line, every
# line carries that suite's own tag. Interleaving would put another suite's tag
# inside the block.
block_defects="$(awk '
  /^=== plugins\/.*\.test\.sh ===$/ { suite = $2; sub(/^plugins\/.*\//, "", suite); inblock = 1; next }
  inblock && /^PASS: / { inblock = 0; next }
  inblock && $0 !~ ("^tag-" suite " line ") && $0 !~ ("^ok: " suite "$") { print "stray line in " suite " block: " $0 }
' <<<"$RUN_OUTPUT")"
if [[ -z "$block_defects" ]]; then
  ok "every suite's output block is contiguous under parallelism"
else
  fail "interleaved output: $block_defects"
fi

rm -f "$probe_dir"/overlap.* "$probe_dir"/running.*
PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "--jobs 1 still honours the allowlist" --root "$r"
for name in p1 p2 p3 s1 s2; do
  [[ -s "$probe_dir/overlap.$name.test.sh" ]] && fail "suite $name overlapped under --jobs 1"
done
ok "no suite overlaps under --jobs 1"

PLUGIN_TEST_JOBS=2 PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "PLUGIN_TEST_JOBS sets the default job count" --root "$r"
assert_output_has "the environment default is reported" "3 across up to 2 job(s)"

# A failing suite inside the parallel group is still reported by name and
# still fails the run; the other members of the group still complete.
write_suite "$r" plugins/p2/p2.test.sh 'echo "boom" >&2; exit 3'
PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 1 "a failure inside the parallel group fails the run" --root "$r" --jobs 3
assert_output_has "the parallel failure is named" "FAIL: plugins/p2/p2.test.sh"
assert_output_has "its siblings still report" "PASS: plugins/p3/p3.test.sh"

# --- the allowlist's stale guard ---------------------------------------------

stale_list="$scratch/stale.txt"
printf 'plugins/gone/gone.test.sh\n' >"$stale_list"
PLUGIN_TEST_SERIAL_LIST="$stale_list" run_runner 2 "an allowlist entry naming no suite fails up front" --root "$r"
assert_output_has "the stale entry is named" "names 'plugins/gone/gone.test.sh', which matches no discovered suite"
assert_output_lacks "nothing ran before the stale guard fired" "=== plugins/"

# --- capture keys survive colliding path shapes -------------------------------
#
# The capture used to be keyed on the suite path with slashes rewritten to a
# double underscore, which collides the moment a path segment already contains
# one: plugins/a__b/c.test.sh and plugins/a/b__c.test.sh flatten to the same
# name. Two colliding suites in one parallel batch then overwrite each other's
# output and exit status, so one real failure can be reported as a pass. Both
# suites here fail, with distinct output, and both must be reported.
r="$(make_root collide)"
write_suite "$r" "plugins/a__b/c.test.sh" 'echo "marker from a__b/c"; exit 1'
write_suite "$r" "plugins/a/b__c.test.sh" 'echo "marker from a/b__c"; exit 1'
write_suite "$r" "plugins/plain/plain.test.sh" 'echo ok'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "colliding path shapes both run in parallel" --root "$r" --jobs 3
assert_output_has "the first colliding suite reports its own failure" "FAIL: plugins/a__b/c.test.sh"
assert_output_has "the second colliding suite reports its own failure" "FAIL: plugins/a/b__c.test.sh"
assert_output_has "the first colliding suite keeps its own output" "marker from a__b/c"
assert_output_has "the second colliding suite keeps its own output" "marker from a/b__c"
assert_output_lacks "neither collides into a missing result" "no result recorded"

# The same pair under --jobs 1: a serial run writes the captures one after the
# other, so a colliding key would silently overwrite rather than race. Keeping
# the case pins the key's uniqueness rather than the scheduling that exposed it.
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "colliding path shapes stay distinct under --jobs 1" --root "$r"
assert_output_has "serial: the first colliding suite still reports" "FAIL: plugins/a__b/c.test.sh"
assert_output_has "serial: the second colliding suite still reports" "FAIL: plugins/a/b__c.test.sh"

# A path containing a colon must not be mis-split by the index-keyed argument
# the worker receives.
r="$(make_root colon)"
write_suite "$r" "plugins/od:d/name.test.sh" 'echo "marker from the colon path"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a path containing a colon runs" --root "$r"
assert_output_has "the colon path is reported whole" "PASS: plugins/od:d/name.test.sh"
assert_output_has "the colon path keeps its output" "marker from the colon path"

# --- the shipped allowlist against the shipped corpus --------------------------
#
# Every entry in scripts/run-plugin-tests-serial.txt must name a suite that
# exists today; the runner's own stale guard is what enforces it, so exercise
# the same reader the runner uses rather than re-implementing it here.
shipped_list="$ROOT/scripts/run-plugin-tests-serial.txt"
stale=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "$line" ]] || continue
  if [[ ! -f "$ROOT/$line" ]]; then
    fail "shipped allowlist names a suite that does not exist: $line"
    stale=1
  fi
done <"$shipped_list"
((stale)) || ok "every shipped serial-allowlist entry names an existing suite"

test_harness::report
