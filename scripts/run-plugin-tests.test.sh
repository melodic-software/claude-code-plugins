#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/run-plugin-tests.sh"
unset PLUGIN_TEST_ADVISORY
unset PLUGIN_TEST_SHARE_WARN_ONLY PLUGIN_TEST_DEADLINE PLUGIN_TEST_LEFT_FILE
export PLUGIN_TEST_SUITE_BUDGET=0
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

scratch=""
fixture_tree::build scratch --label run-plugin-tests

make_root() {
  local r="$scratch/$1"
  mkdir -p "$r/plugins" "$r/.claude/hooks"
  printf '%s' "$r"
}

write_suite() {
  local path="$1/$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\n%s\n' "$3" >"$path"
}

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

assert_error_count() {
  local label="$1" want="$2" got
  got="$(grep -c '^::error title=' <<<"$RUN_OUTPUT" || true)"
  if [[ "$got" -eq "$want" ]]; then
    ok "$label"
  else
    fail "$label: expected $want ::error annotation(s), got $got; output: $RUN_OUTPUT"
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
export PLUGIN_TEST_ADVISORY_LIST="$empty_list"
export PLUGIN_TEST_SUITE_EXCEPTIONS="$empty_list"

r="$(make_root pass)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "ok: b"'
write_suite "$r" .claude/hooks/h.test.sh 'echo "ok: h"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "every suite passing exits 0" --root "$r"
assert_output_has "each suite is announced" "=== plugins/a/a.test.sh ==="
assert_output_has "repo-local hook suites are discovered" "PASS: .claude/hooks/h.test.sh"
assert_output_has "the all-green summary line" "All plugin tests passed."
assert_output_has "the suite count is reported" "Suites: 3 (0 serial, 3 across up to 1 job(s))"

PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "--list exits 0" --list --root "$r"
if [[ "$RUN_OUTPUT" == $'.claude/hooks/h.test.sh\nplugins/a/a.test.sh\nplugins/b/b.test.sh' ]]; then
  ok "--list prints the discovered corpus and runs nothing"
else
  fail "--list: got [$RUN_OUTPUT]"
fi

r="$(make_root scripts-lib)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" scripts/check-x.test.sh 'echo "ok: gate self-test"'
write_suite "$r" scripts/lib/helper.test.sh 'echo "ok: scripts lib"'
write_suite "$r" lib/shared.test.sh 'echo "ok: shared lib"'
write_suite "$r" .github/scripts/x/y.test.sh 'echo "ok: github"'
write_suite "$r" tools/elsewhere.test.sh 'echo "ok: never discovered"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "scripts/, lib/ and .github/ suites run with the corpus" --root "$r"
assert_output_has "a scripts/ suite is discovered" "PASS: scripts/check-x.test.sh"
assert_output_has "a scripts/lib/ suite is discovered" "PASS: scripts/lib/helper.test.sh"
assert_output_has "a lib/ suite is discovered" "PASS: lib/shared.test.sh"
assert_output_has "a .github/ suite is discovered" "PASS: .github/scripts/x/y.test.sh"
assert_output_lacks "a suite outside the five roots is not discovered" "tools/elsewhere.test.sh"

r="$(make_root fail)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "FAIL: b broke" >&2; exit 1'
write_suite "$r" plugins/c/c.test.sh 'echo "ok: c"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "one failing suite exits 1" --root "$r"
assert_output_has "the failing suite is named" "FAIL: plugins/b/b.test.sh"
assert_output_has "suites after the failure still run" "PASS: plugins/c/c.test.sh"
assert_output_has "the failure summary line" "One or more plugin tests failed."

r="$(make_root excerpt)"
# shellcheck disable=SC2016
write_suite "$r" plugins/a/a.test.sh 'echo "FAIL: case one broke"; for i in $(seq 1 100); do echo "filler $i"; done; echo "::error::from the suite"; echo "last line"; exit 1'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a long failing suite exits 1" --root "$r"
excerpt="${RUN_OUTPUT#*::error title=plugins/a/a.test.sh::plugins/a/a.test.sh failed (exit 1)}"
if [[ "$excerpt" == $'\n  Failing lines of plugins/a/a.test.sh:\n    | FAIL: case one broke\n  Last 80 lines of plugins/a/a.test.sh:\n    | filler 23\n'* &&
  "$excerpt" == *$'\n    | filler 100\n    | ::error::from the suite\n    | last line\n'* ]]; then
  ok "the annotation is followed by the prefixed FAIL line and the last 80 lines"
else
  fail "excerpt: got [$excerpt]"
fi
if [[ "$(grep -c -E '^[[:space:]]*::error' <<<"$RUN_OUTPUT")" -eq 2 ]]; then
  ok "the reprinted ::error line is not a workflow command"
else
  fail "reprinted ::error: got [$RUN_OUTPUT]"
fi

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
assert_output_has "the empty corpus is named" "no test suites found"

r="$(make_root argv)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "--jobs 0 is rejected" --root "$r" --jobs 0
assert_output_has "the bad job count is named" "--jobs must be a positive integer (got '0')"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "an unknown flag prints usage" --root "$r" --parallel
assert_output_has "usage names the flags" "usage: run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR]"

r="$(make_root timings)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "FAIL: b broke" >&2; exit 3'
write_suite "$r" plugins/c/c.test.sh 'echo "ok: c"'
tfile="$scratch/timings.tsv"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "one suite argument runs that suite alone" --root "$r" --timings "$tfile" plugins/a/a.test.sh
assert_output_lacks "a suite not named is not run" "plugins/c/c.test.sh"
one_row=$'^plugins/a/a\\.test\\.sh\t[0-9]+\t0$'
if [[ "$(<"$tfile")" =~ $one_row ]]; then
  ok "--timings writes one row of path, seconds and exit code"
else
  fail "--timings one suite: got [$(<"$tfile")]"
fi
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "--timings keeps the exit contract" --root "$r" --timings="$tfile"
if [[ "$(cut -f1,3 "$tfile")" == $'plugins/a/a.test.sh\t0\nplugins/b/b.test.sh\t3\nplugins/c/c.test.sh\t0' ]]; then
  ok "--timings overwrites the file with a row per suite in corpus order, a failure's exit code kept"
else
  fail "--timings whole corpus: got [$(<"$tfile")]"
fi
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a suite argument that is not a file is rejected" --root "$r" plugins/nope.test.sh
assert_output_has "the missing suite is named" "suite argument 'plugins/nope.test.sh' is not a file"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a --timings file in a missing directory is rejected" --root "$r" --timings "$scratch/no-such-dir/t.tsv"
assert_output_has "the missing directory is named" "--timings directory not found"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "an empty --timings value is a usage error" --root "$r" --timings=
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "without --timings the run is unchanged" --root "$r" plugins/c/c.test.sh
assert_output_has "the TIME line still prints" "TIME: plugins/c/c.test.sh "

r="$(make_root plugin-data)"
# The suite body is written literally: the $ must survive into the spawned script.
# shellcheck disable=SC2016
write_suite "$r" plugins/a/sees-unset.test.sh \
  'if [[ -n "${CLAUDE_PLUGIN_DATA+x}" ]]; then printf "FAIL: CLAUDE_PLUGIN_DATA=%s\n" "$CLAUDE_PLUGIN_DATA" >&2; exit 1; fi; echo "ok: CLAUDE_PLUGIN_DATA unset"'
plugin_data_was_set=0
plugin_data_saved=""
if [[ -n "${CLAUDE_PLUGIN_DATA+x}" ]]; then
  plugin_data_was_set=1
  plugin_data_saved="$CLAUDE_PLUGIN_DATA"
fi
export CLAUDE_PLUGIN_DATA="/x/codex-openai-codex"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a spawned suite sees an inherited CLAUDE_PLUGIN_DATA unset" --root "$r"
assert_output_has "the suite reports CLAUDE_PLUGIN_DATA unset" "ok: CLAUDE_PLUGIN_DATA unset"
if ((plugin_data_was_set)); then
  export CLAUDE_PLUGIN_DATA="$plugin_data_saved"
else
  unset CLAUDE_PLUGIN_DATA
fi

r="$(make_root git-config)"
hostile="$scratch/hostile.gitconfig"
printf '[user]\n\tname = host\n\temail = host@example.invalid\n[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /bin/false\n' >"$hostile"
# The suite bodies are written literally: the $ must survive into the spawned scripts.
# shellcheck disable=SC2016
write_suite "$r" plugins/a/commits.test.sh \
  'd="$(dirname "$0")/repo" && git init -q "$d" && git -C "$d" commit -q --allow-empty -m x && echo "ok: committed as $(git -C "$d" log -1 --format=%ae)" && git config --global fixture.leak a'
# shellcheck disable=SC2016
write_suite "$r" plugins/b/reads.test.sh \
  'if v=$(git config --global fixture.leak); then echo "FAIL: fixture.leak=$v" >&2; exit 1; fi; echo "ok: no leaked global setting"'
GIT_CONFIG_GLOBAL="$hostile" PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a suite commits under a host config that signs every commit" --root "$r"
assert_output_has "the fixture commit carries the test identity" "ok: committed as t@t.test"
assert_output_lacks "the host signing program never ran" "failed to sign"
assert_output_has "a global setting one suite writes does not reach the next" "ok: no leaked global setting"

r="$(make_root multicorejit)"
# shellcheck disable=SC2016
write_suite "$r" plugins/a/env.test.sh 'echo "jit=${DOTNET_MultiCoreJitMinNumCpus-unset} xdg=${XDG_CACHE_HOME-unset}"'
DOTNET_MultiCoreJitMinNumCpus=1 XDG_CACHE_HOME=/host/cache PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a suite reports its .NET and cache environment" --root "$r"
assert_output_has "a suite runs with MultiCoreJit off over the host's value, and the host's XDG_CACHE_HOME" "jit=65535 xdg=/host/cache"

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
serial_last="$(grep -n '^PASS: plugins/s' <<<"$RUN_OUTPUT" | tail -n 1 | cut -d: -f1)"
parallel_first="$(grep -n '^PASS: plugins/p' <<<"$RUN_OUTPUT" | head -n 1 | cut -d: -f1)"
if [[ -n "$serial_last" && -n "$parallel_first" ]] && ((serial_last < parallel_first)); then
  ok "serial suites finish before the parallel group starts"
else
  fail "serial suites did not all finish before the parallel group (serial last line $serial_last, parallel first line $parallel_first)"
fi
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
picked="$scratch/selection-serial.txt"
printf 'plugins/p1/p1.test.sh\nplugins/p3/p3.test.sh\nplugins/s1/s1.test.sh\n' >"$picked"
PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "a supplied selection carrying a serial suite exits 0" \
  --root "$r" --jobs 3 --suites-from "$picked"
assert_output_has "the supplied selection is split serial-first" "Suites: 3 (1 serial, 2 across up to 3 job(s))"
assert_output_lacks "an allowlisted suite the selection did not draw stays unrun" "=== plugins/s2/s2.test.sh ==="
if [[ -s "$probe_dir/overlap.s1.test.sh" ]]; then
  fail "selected serial suite s1 overlapped another suite: $(cat "$probe_dir/overlap.s1.test.sh")"
else
  ok "a serial suite drawn by --suites-from still runs alone"
fi
sel_overlaps=0
for name in p1 p3; do
  [[ -s "$probe_dir/overlap.$name.test.sh" ]] && sel_overlaps=$((sel_overlaps + 1))
done
if ((sel_overlaps > 0)); then
  ok "the selected parallel suites still ran concurrently ($sel_overlaps of 2 probes saw a sibling)"
else
  fail "no selected parallel probe saw a sibling; --suites-from collapsed the group to serial"
fi
sel_serial_last="$(grep -n '^PASS: plugins/s1' <<<"$RUN_OUTPUT" | tail -n 1 | cut -d: -f1)"
sel_parallel_first="$(grep -n '^PASS: plugins/p' <<<"$RUN_OUTPUT" | head -n 1 | cut -d: -f1)"
if [[ -n "$sel_serial_last" && -n "$sel_parallel_first" ]] && ((sel_serial_last < sel_parallel_first)); then
  ok "the selected serial suite finishes before the selected parallel group starts"
else
  fail "the selected serial suite did not finish first (serial line $sel_serial_last, parallel first line $sel_parallel_first)"
fi

rm -f "$probe_dir"/overlap.* "$probe_dir"/running.*
PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "--jobs 1 still honors the allowlist" --root "$r"
for name in p1 p2 p3 s1 s2; do
  [[ -s "$probe_dir/overlap.$name.test.sh" ]] && fail "suite $name overlapped under --jobs 1"
done
ok "no suite overlaps under --jobs 1"

PLUGIN_TEST_JOBS=2 PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 0 "PLUGIN_TEST_JOBS sets the default job count" --root "$r"
assert_output_has "the environment default is reported" "3 across up to 2 job(s)"

write_suite "$r" plugins/p2/p2.test.sh 'echo "boom" >&2; exit 3'
PLUGIN_TEST_SERIAL_LIST="$serial_list" run_runner 1 "a failure inside the parallel group fails the run" --root "$r" --jobs 3
assert_output_has "the parallel failure is named" "FAIL: plugins/p2/p2.test.sh"
assert_output_has "its siblings still report" "PASS: plugins/p3/p3.test.sh"

stale_list="$scratch/stale.txt"
printf 'plugins/gone/gone.test.sh\n' >"$stale_list"
PLUGIN_TEST_SERIAL_LIST="$stale_list" run_runner 2 "an allowlist entry naming no suite fails up front" --root "$r"
assert_output_has "the stale entry is named" "names 'plugins/gone/gone.test.sh', which matches no discovered suite"
assert_output_lacks "nothing ran before the stale guard fired" "=== plugins/"

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

PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "colliding path shapes stay distinct under --jobs 1" --root "$r"
assert_output_has "serial: the first colliding suite still reports" "FAIL: plugins/a__b/c.test.sh"
assert_output_has "serial: the second colliding suite still reports" "FAIL: plugins/a/b__c.test.sh"

r="$(make_root colon)"
write_suite "$r" "plugins/od:d/name.test.sh" 'echo "marker from the colon path"'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a path containing a colon runs" --root "$r"
assert_output_has "the colon path is reported whole" "PASS: plugins/od:d/name.test.sh"
assert_output_has "the colon path keeps its output" "marker from the colon path"

r="$(make_root longest-first)"
for name in a b c d e s; do
  write_suite "$r" "plugins/$name/$name.test.sh" 'echo ok'
done
seconds_list="$scratch/suite-seconds.txt"
printf '%s\n' "# seconds" "plugins/c/c.test.sh 10" "plugins/b/b.test.sh 30" "plugins/e/e.test.sh 30" \
  "plugins/s/s.test.sh 999" >"$seconds_list"
serial_s="$scratch/serial-s.txt"
printf 'plugins/s/s.test.sh\n' >"$serial_s"
PLUGIN_TEST_SECONDS_LIST="$seconds_list" PLUGIN_TEST_SERIAL_LIST="$serial_s" run_runner 0 "a run ordered by suite-seconds exits 0" --root "$r"
order="$(sed -n 's|^PASS: plugins/\(.\)/.*|\1|p' <<<"$RUN_OUTPUT" | tr -d '\n')"
if [[ "$order" == "sbecad" ]]; then
  ok "serial first, then the parallel group longest first with unlisted suites last in sorted order"
else
  fail "start order: expected sbecad, got $order"
fi
assert_output_has "the summary is unchanged by the ordering" "Suites: 6 (1 serial, 5 across up to 1 job(s))"

PLUGIN_TEST_SECONDS_LIST="$scratch/no-such-seconds.txt" PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a missing seconds file runs in sorted order" --root "$r"
order="$(sed -n 's|^PASS: plugins/\(.\)/.*|\1|p' <<<"$RUN_OUTPUT" | tr -d '\n')"
if [[ "$order" == "abcdes" ]]; then
  ok "with no seconds file the parallel group starts in sorted order"
else
  fail "start order without a seconds file: expected abcdes, got $order"
fi

r="$(make_root shard)"
for name in a b c d e f g; do
  write_suite "$r" "plugins/$name/$name.test.sh" 'echo ok'
done
shard_list="$scratch/shard-serial.txt"
printf 'plugins/b/b.test.sh\nplugins/c/c.test.sh\n' >"$shard_list"
PLUGIN_TEST_SERIAL_LIST="$shard_list" run_runner 0 "unsharded reference run" --root "$r"
whole="$(grep '^PASS: ' <<<"$RUN_OUTPUT" | sort)"
legs=""
for leg in 0 1 2; do
  PLUGIN_TEST_SERIAL_LIST="$shard_list" run_runner 0 "leg $leg of 3 exits 0" --root "$r" --jobs 2 --shard "$leg/3"
  legs+="$(grep '^PASS: ' <<<"$RUN_OUTPUT")"$'\n'
  [[ "$leg" == 1 ]] && assert_output_has "leg 1 runs its own serial subset" "Suites: 2 (1 serial, 1 across up to 2 job(s))"
done
assert_output_has "the leg reports what it kept" "shard: leg 2 of 3 keeps 2 of 7 suite(s)."
if [[ "$(grep . <<<"$legs" | sort)" == "$whole" ]]; then
  ok "the legs are disjoint and their union is the unsharded corpus"
else
  fail "legs do not partition the corpus; unsharded: $whole; legs: $legs"
fi

r="$(make_root shard-empty)"
write_suite "$r" plugins/a/a.test.sh 'echo ok'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a leg that draws nothing exits 0" --root "$r" --shard 1/2
assert_output_lacks "the empty leg runs nothing" "=== plugins/"

for spec in 2/2 x 1 1/0 ''; do
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "--shard '$spec' is rejected" --root "$r" --shard "$spec"
done
assert_output_has "the bad shard spec is named" "--shard wants <index>/<total>"

r="$(make_root suites-from)"
write_suite "$r" plugins/a/a.test.sh 'echo "ok: a"'
write_suite "$r" plugins/b/b.test.sh 'echo "ok: b"'
write_suite "$r" tools/outside.test.sh 'echo "ok: outside"'
selection="$scratch/selection.txt"
printf 'plugins/a/a.test.sh\ntools/outside.test.sh\n' >"$selection"
serial_b="$scratch/serial-b.txt"
printf 'plugins/b/b.test.sh\n' >"$serial_b"
PLUGIN_TEST_SERIAL_LIST="$serial_b" run_runner 0 "--suites-from runs exactly the supplied selection" \
  --root "$r" --suites-from "$selection"
assert_output_has "a listed suite runs" "PASS: plugins/a/a.test.sh"
assert_output_has "a listed suite outside the discovered corpus runs" "PASS: tools/outside.test.sh"
assert_output_lacks "an unlisted suite does not run" "=== plugins/b/b.test.sh ==="

missing="$scratch/selection-missing.txt"
printf 'plugins/a/a.test.sh\nplugins/nope/nope.test.sh\n' >"$missing"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a listed path that is not a file is rejected" \
  --root "$r" --suites-from "$missing"
assert_output_has "the missing path is named" "plugins/nope/nope.test.sh"

PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a missing --suites-from file is rejected" \
  --root "$r" --suites-from "$scratch/no-such-list.txt"

empty_selection="$scratch/selection-empty.txt"
: >"$empty_selection"
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "an empty selection exits 0 having run nothing" \
  --root "$r" --suites-from "$empty_selection"
assert_output_lacks "the empty selection runs nothing" "=== plugins/"

r="$(make_root advisory)"
write_suite "$r" plugins/planning/shared/tests/ui-a.test.sh 'echo "FAIL: ui timing" >&2; exit 1'
# shellcheck disable=SC2016 # the suite expands it, not this script
write_suite "$r" plugins/b/b.test.sh 'echo "ok: b"; echo "suite sees nonce: [${advisory_nonce:-}]"'
advisory_list="$scratch/advisory.txt"
printf '# fixture\nplugins/planning/shared/tests/ui-a.test.sh\n' >"$advisory_list"

PLUGIN_TEST_ADVISORY=1 PLUGIN_TEST_ADVISORY_LIST="$advisory_list" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "on main, a failing advisory suite does not fail the run" --root "$r"
assert_output_has "on main, the advisory failure is a warning titled by its suite" \
  "::warning title=plugins/planning/shared/tests/ui-a.test.sh::plugins/planning/shared/tests/ui-a.test.sh failed (exit 1) but is advisory on this run"
assert_output_has "on main, the suite's FAIL block still prints" "FAIL: plugins/planning/shared/tests/ui-a.test.sh"
assert_output_has "on main, the summary names the advisory failure" "1 advisory suite(s) FAILED"
assert_output_lacks "on main, the run does not claim all green" "All plugin tests passed."
assert_output_lacks "on main, the advisory failure gets no error annotation" "::error"
nonce="$(sed -n 's/^Advisory nonce: \([0-9a-f]\{16\}\)$/\1/p' <<<"$RUN_OUTPUT")"
before_blocks="$(sed -n '/^=== /q; p' <<<"$RUN_OUTPUT")"
if [[ -n "$nonce" && "$before_blocks" == *"Advisory nonce: $nonce"* &&
  "$RUN_OUTPUT" == *"failed (exit 1) but is advisory on this run (nonce $nonce;"* ]]; then
  ok "on main, a 16-hex nonce prints before any suite block and the warning carries it"
else
  fail "on main, no nonce before the blocks or in the warning: $RUN_OUTPUT"
fi
assert_output_has "no suite inherits the nonce" "suite sees nonce: []"

PLUGIN_TEST_ADVISORY_LIST="$advisory_list" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "on a pull request, the same advisory-listed failure fails the run" --root "$r"
assert_output_lacks "on a pull request, no advisory warning is printed" "::warning"
assert_output_lacks "on a pull request, no nonce is printed" "Advisory nonce:"
assert_output_has "on a pull request, the failure summary line" "One or more plugin tests failed."

r="$(make_root advisory-other)"
write_suite "$r" plugins/planning/shared/tests/ui-a.test.sh 'echo "ok: ui"'
write_suite "$r" plugins/b/b.test.sh 'echo "FAIL: b broke" >&2; exit 1'
PLUGIN_TEST_ADVISORY=1 PLUGIN_TEST_ADVISORY_LIST="$advisory_list" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "on main, a failing suite not on the advisory list still fails the run" --root "$r"
assert_output_lacks "on main, a non-advisory failure gets no warning" "::warning"

assert_output_has "a failing suite gets its own error annotation" \
  "::error title=plugins/b/b.test.sh::plugins/b/b.test.sh failed (exit 1)"
assert_error_count "a failing suite gets exactly one error annotation" 1

r="$(make_root annotate-escape)"
write_suite "$r" "plugins/od:d,x/name.test.sh" 'exit 4'
write_suite "$r" "plugins/ok/ok.test.sh" 'echo ok'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a failing suite with : and , in its path fails the run" --root "$r"
assert_output_has "the annotation title escapes : and ," \
  "::error title=plugins/od%3Ad%2Cx/name.test.sh::plugins/od:d,x/name.test.sh failed (exit 4)"
assert_error_count "the escaped suite gets exactly one error annotation" 1

r="$(make_root annotate-percent)"
write_suite "$r" "plugins/p%q/x.test.sh" 'exit 5'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a failing suite with % in its path fails the run" --root "$r"
assert_output_has "the annotation escapes % in the title and the message" \
  "::error title=plugins/p%25q/x.test.sh::plugins/p%25q/x.test.sh failed (exit 5)"
assert_error_count "the percent suite gets exactly one error annotation" 1

stale_advisory="$scratch/advisory-stale.txt"
printf 'plugins/gone/gone.test.sh\n' >"$stale_advisory"
PLUGIN_TEST_ADVISORY_LIST="$stale_advisory" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 2 "an advisory entry that matches no suite is rejected" --root "$r"
assert_output_has "the stale advisory entry is named" "plugins/gone/gone.test.sh"

r="$(make_root budget)"
write_suite "$r" plugins/slow/slow.test.sh 'sleep 2.1; echo "ok: slow"'
write_suite "$r" plugins/quick/quick.test.sh 'echo "ok: quick"'
no_seconds="$scratch/no-such-seconds.txt"
PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a suite over its share fails the run" --root "$r" --jobs 2 --budget 1
assert_output_has "the over-share suite is named with its time and share" "FAIL: plugins/slow/slow.test.sh took "
assert_output_has "the share it went over is named" "s, over its 1s share of the budget"
assert_output_lacks "a suite inside its share is not failed" "FAIL: plugins/quick/quick.test.sh"
assert_error_count "the over-share suite gets one error annotation" 1
assert_output_has "the overrun of the whole run is reported" "OVER BUDGET: the suites took "
assert_output_has "the overrun names the slowest suite" "s plugins/slow/slow.test.sh"

PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "without --budget no suite is timed against a share" --root "$r" --jobs 2
assert_output_lacks "without --budget no suite is failed for its time" "share of the budget"
assert_output_lacks "without --budget no overrun is reported" "OVER BUDGET"
if grep -qE '^TIME: plugins/slow/slow\.test\.sh [0-9]+s$' <<<"$RUN_OUTPUT" &&
  grep -qE '^TIME: plugins/quick/quick\.test\.sh [0-9]+s$' <<<"$RUN_OUTPUT"; then
  ok "without --budget each suite's wall seconds still print"
else
  fail "without --budget a suite's TIME line is missing; output: $RUN_OUTPUT"
fi

budget_seconds="$scratch/budget-seconds.txt"
printf '%s\n' "# seconds" "plugins/slow/slow.test.sh 5" >"$budget_seconds"
PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 PLUGIN_TEST_SECONDS_LIST="$budget_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a listed median raises the share, and an overrun alone does not fail" \
  --root "$r" --jobs 2 --budget 1
assert_output_lacks "the listed suite inside its 5 s share is not failed" "over its"
assert_output_has "the overrun is still reported" "OVER BUDGET: the suites took "

PLUGIN_TEST_SECONDS_LIST="$budget_seconds" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "a run inside the budget says so" --root "$r" --budget 600
assert_output_has "the time against the budget is reported" "s of the 600s budget."

for bad in 0 x -1 ''; do
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "--budget '$bad' is rejected" --root "$r" --budget "$bad"
done
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "an empty --budget= is rejected, not a run with no budget" --root "$r" --budget=
PLUGIN_TEST_SHARE_MARGIN=0 PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a zero share margin is rejected" --root "$r" --budget 60
assert_output_has "the bad margin is named" "PLUGIN_TEST_SHARE_MARGIN must be a positive integer (got '0')"

PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=7 PLUGIN_TEST_SECONDS_LIST="$budget_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a run with an unlisted suite still passes" --root "$r" --budget 600
assert_output_has "the unlisted suite is named with its default share" \
  "note: plugins/quick/quick.test.sh has no median in $budget_seconds, so it gets the default 7s share"
assert_output_lacks "a listed suite is not named as unlisted" "note: plugins/slow/slow.test.sh"

PLUGIN_TEST_SHARE_WARN_ONLY=1 PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 \
  PLUGIN_TEST_SECONDS_LIST="$no_seconds" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "in the local gate a passing suite over its share does not fail the run" --root "$r" --jobs 2 --budget 1
assert_output_has "the over-share suite is named as a warning" "OVER SHARE: plugins/slow/slow.test.sh took "
assert_output_has "the warning annotation names the suite" \
  "::warning title=plugins/slow/slow.test.sh::plugins/slow/slow.test.sh took "
assert_output_lacks "the passing over-share suite is not failed" "FAIL: plugins/slow/slow.test.sh"
assert_error_count "the passing over-share suite gets no error annotation" 0

fail_root="$(make_root warn-only-fail)"
write_suite "$fail_root" plugins/slowfail/slowfail.test.sh 'sleep 2.1; echo "FAIL: slow and broken" >&2; exit 1'
PLUGIN_TEST_SHARE_WARN_ONLY=1 PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 \
  PLUGIN_TEST_SECONDS_LIST="$no_seconds" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "in the local gate a failing suite over its share still fails the run" --root "$fail_root" --budget 1
assert_output_has "the failing suite is failed by its exit" "plugins/slowfail/slowfail.test.sh failed (exit 1)"
assert_output_has "its overrun is still only a warning" "OVER SHARE: plugins/slowfail/slowfail.test.sh took "
assert_error_count "only the exit gets an error annotation" 1

PLUGIN_TEST_SHARE_WARN_ONLY=0 PLUGIN_TEST_SHARE_MARGIN=1 PLUGIN_TEST_SHARE_DEFAULT=1 \
  PLUGIN_TEST_SECONDS_LIST="$no_seconds" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "with the switch at 0 a passing suite over its share fails the run" --root "$r" --jobs 2 --budget 1
assert_output_has "the over-share suite is failed by name" "FAIL: plugins/slow/slow.test.sh took "

PLUGIN_TEST_SHARE_WARN_ONLY=yes PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 2 "a share warn-only switch other than 0 or 1 is rejected" --root "$fail_root" --budget 60
assert_output_has "the bad switch is named" "PLUGIN_TEST_SHARE_WARN_ONLY must be 0 or 1 (got 'yes')"

deadline_root="$(make_root deadline)"
for s in a b c d e f; do
  write_suite "$deadline_root" "plugins/$s/$s.test.sh" 'sleep 6; echo "ok"'
done
left_file="$scratch/left.txt"
start=$SECONDS
printf -v now '%(%s)T' -1
PLUGIN_TEST_DEADLINE=$((now + 5)) PLUGIN_TEST_LEFT_FILE="$left_file" PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a run past its deadline stops launching and does not fail" \
  --root "$deadline_root" --budget 5
elapsed=$((SECONDS - start))
if ((elapsed <= 20)); then
  ok "the run ends within its deadline plus one suite (${elapsed}s)"
else
  fail "the run took ${elapsed}s against a 5 s deadline and 6 s suites; output: $RUN_OUTPUT"
fi
assert_output_has "the suite launched before the deadline ran" "PASS: plugins/a/a.test.sh"
assert_output_lacks "a suite past the deadline did not run" "PASS: plugins/f/f.test.sh"
assert_output_has "each suite left is named on the run's output" "LEFT TO CI: plugins/f/f.test.sh"
assert_output_lacks "a run that left suites does not read as a full pass" "All plugin tests passed."
assert_output_lacks "a suite left is not a suite that never reported" "no result recorded"
left_want=$'plugins/b/b.test.sh\nplugins/c/c.test.sh\nplugins/d/d.test.sh\nplugins/e/e.test.sh\nplugins/f/f.test.sh'
if [[ "$(cat "$left_file" 2>/dev/null)" == "$left_want" ]]; then
  ok "the left file names every suite not launched, and only those"
else
  fail "left file: $(cat "$left_file" 2>/dev/null); output: $RUN_OUTPUT"
fi

quick_root="$(make_root deadline-quick)"
for s in a b c; do
  write_suite "$quick_root" "plugins/$s/$s.test.sh" 'echo "ok"'
done
PLUGIN_TEST_SECONDS_LIST="$no_seconds" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "--budget alone ends nothing" --root "$quick_root" --budget 1
assert_output_has "--budget alone runs the last suite" "PASS: plugins/c/c.test.sh"
assert_output_lacks "--budget alone leaves nothing" "LEFT TO CI"

deadline_serial="$scratch/deadline-serial.txt"
printf '%s\n' plugins/a/a.test.sh >"$deadline_serial"
tfile="$scratch/deadline-timings.tsv"
rm -f "$left_file"
PLUGIN_TEST_DEADLINE=1 PLUGIN_TEST_LEFT_FILE="$left_file" PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$deadline_serial" run_runner 0 "a deadline already past launches nothing" \
  --root "$quick_root" --jobs 2 --budget 1 --timings "$tfile"
assert_output_lacks "the serial suite did not run" "PASS: plugins/a/a.test.sh"
assert_output_lacks "the parallel suite did not run" "PASS: plugins/c/c.test.sh"
assert_output_has "the serial suite is named as left" "LEFT TO CI: plugins/a/a.test.sh"
assert_output_has "the parallel suite is named as left" "LEFT TO CI: plugins/c/c.test.sh"
if [[ ! -s "$tfile" && "$(wc -l <"$left_file")" -eq 3 ]]; then
  ok "no timing row for a suite that never ran"
else
  fail "timings: $(cat "$tfile"); left: $(cat "$left_file" 2>/dev/null)"
fi

deadline_fail="$(make_root deadline-fail)"
write_suite "$deadline_fail" plugins/a/a.test.sh 'sleep 6; echo "FAIL: broken" >&2; exit 1'
write_suite "$deadline_fail" plugins/b/b.test.sh 'echo "ok"'
printf -v now '%(%s)T' -1
PLUGIN_TEST_DEADLINE=$((now + 5)) PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a failed suite still fails a run that left others" \
  --root "$deadline_fail" --budget 5
assert_output_has "the failed suite is named" "plugins/a/a.test.sh failed (exit 1)"
assert_output_has "the suite left is named beside it" "LEFT TO CI: plugins/b/b.test.sh"

deadline_inherit="$(make_root deadline-inherit)"
# shellcheck disable=SC2016 # the fixture suite expands these, not this file.
write_suite "$deadline_inherit" plugins/a/a.test.sh 'echo "saw deadline=${PLUGIN_TEST_DEADLINE-unset} left=${PLUGIN_TEST_LEFT_FILE-unset}"'
printf -v now '%(%s)T' -1
PLUGIN_TEST_DEADLINE=$((now + 600)) PLUGIN_TEST_LEFT_FILE="$left_file" PLUGIN_TEST_SECONDS_LIST="$no_seconds" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 0 "a run inside its deadline is a plain pass" \
  --root "$deadline_inherit" --budget 600
assert_output_has "a suite does not inherit the deadline" "saw deadline=unset left=unset"
assert_output_has "a run inside its deadline reads as a full pass" "All plugin tests passed."

deadline_forge="$(make_root deadline-forge)"
# shellcheck disable=SC2016 # the fixture suite expands this, not this file.
write_suite "$deadline_forge" plugins/a/a.test.sh ': >"$PLUGIN_TEST_LOG_DIR/000000.left"; exit 1'
PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 1 "a suite's own left marker does not hide its failure" --root "$deadline_forge"
assert_output_has "the failure is still named" "plugins/a/a.test.sh failed (exit 1)"
assert_output_lacks "a suite that ran is not left" "LEFT TO CI"
printf -v now '%(%s)T' -1
PLUGIN_TEST_DEADLINE=$((now + 600)) PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "a recorded result wins over a left marker inside a deadline" --root "$deadline_forge"
deadline_killed="$(make_root deadline-killed)"
# shellcheck disable=SC2016 # the fixture suite expands these, not this file.
write_suite "$deadline_killed" plugins/a/a.test.sh ': >"$PLUGIN_TEST_LOG_DIR/000000.left"; kill -9 "$PPID"'
killed_serial="$scratch/killed-serial.txt"
printf '%s\n' plugins/a/a.test.sh >"$killed_serial"
PLUGIN_TEST_SERIAL_LIST="$killed_serial" run_runner 1 "with no deadline a left marker does not excuse a missing result" --root "$deadline_killed"
assert_output_has "the missing result is named" "no result recorded"

for bad in x -1 ''; do
  PLUGIN_TEST_DEADLINE="$bad" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
    run_runner 2 "a deadline of '$bad' is rejected" --root "$deadline_inherit"
done
assert_output_has "the bad deadline is named" "PLUGIN_TEST_DEADLINE must be epoch seconds (got '')"

no_exceptions="$scratch/no-such-exceptions.txt"
PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_WARN=1 PLUGIN_TEST_SUITE_CEILING=60 \
  PLUGIN_TEST_SUITE_EXCEPTIONS="$no_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "a suite over the threshold and under the ceiling warns and exits 0" --root "$r" --jobs 2
assert_output_has "the slow suite is named over the threshold" "SLOW: plugins/slow/slow.test.sh took "
assert_output_has "the warning annotation names the suite" "::warning title=plugins/slow/slow.test.sh::plugins/slow/slow.test.sh took "
assert_output_lacks "a suite under the threshold is not named" "SLOW: plugins/quick/quick.test.sh"
assert_error_count "a suite under the ceiling gets no error annotation" 0

PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_WARN=1 PLUGIN_TEST_SUITE_CEILING=1 \
  PLUGIN_TEST_SUITE_EXCEPTIONS="$no_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 1 "a suite over the ceiling fails the run" --root "$r" --jobs 2
assert_output_has "the over-ceiling suite's time is named with its ceiling" "s, over its 1s per-suite ceiling"
if grep -qx 'FAIL: plugins/slow/slow.test.sh' <<<"$RUN_OUTPUT"; then
  ok "the over-ceiling suite gets a bare FAIL line that log readers attribute"
else
  fail "no bare 'FAIL: plugins/slow/slow.test.sh' line; output: $RUN_OUTPUT"
fi
assert_output_lacks "a suite inside the ceiling is not failed" "FAIL: plugins/quick/quick.test.sh"
assert_error_count "the over-ceiling suite gets one error annotation" 1

exceptions="$scratch/exceptions.txt"
printf '%s\n' "# fixture" "plugins/slow/slow.test.sh 60 # needs more" >"$exceptions"
PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_WARN=1 PLUGIN_TEST_SUITE_CEILING=1 \
  PLUGIN_TEST_SUITE_EXCEPTIONS="$exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "an exception row raises its suite's ceiling" --root "$r" --jobs 2
assert_output_has "the excepted suite still warns over the threshold" "SLOW: plugins/slow/slow.test.sh took "

PLUGIN_TEST_SUITE_BUDGET='' GITHUB_ACTIONS=true PLUGIN_TEST_SUITE_WARN=1 PLUGIN_TEST_SUITE_CEILING=60 \
  PLUGIN_TEST_SUITE_EXCEPTIONS="$no_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "on GitHub Actions the suite budget is on by default" --root "$r" --jobs 2
assert_output_has "the CI default times the slow suite" "SLOW: plugins/slow/slow.test.sh took "

PLUGIN_TEST_SUITE_BUDGET='' GITHUB_ACTIONS='' PLUGIN_TEST_SUITE_WARN=1 PLUGIN_TEST_SUITE_CEILING=1 \
  PLUGIN_TEST_SUITE_EXCEPTIONS="$no_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 0 "outside GitHub Actions the suite budget is off by default" --root "$r" --jobs 2
assert_output_lacks "no suite is timed against the threshold" "SLOW:"
assert_output_lacks "no suite is failed for its time" "per-suite ceiling"

stale_exceptions="$scratch/exceptions-stale.txt"
printf 'plugins/gone/gone.test.sh 60\n' >"$stale_exceptions"
PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_EXCEPTIONS="$stale_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 2 "an exception that matches no suite is rejected" --root "$r"
assert_output_has "the stale exception is named" "names 'plugins/gone/gone.test.sh', which matches no discovered suite"

bad_exceptions="$scratch/exceptions-bad.txt"
printf 'plugins/slow/slow.test.sh\n' >"$bad_exceptions"
PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_EXCEPTIONS="$bad_exceptions" PLUGIN_TEST_SERIAL_LIST="$empty_list" \
  run_runner 2 "an exception row with no ceiling is rejected" --root "$r"
assert_output_has "the malformed row is named" "row for 'plugins/slow/slow.test.sh' wants '<suite> <ceiling-seconds>'"

PLUGIN_TEST_SUITE_BUDGET=yes PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a suite budget switch other than 0 or 1 is rejected" --root "$r"
PLUGIN_TEST_SUITE_BUDGET=1 PLUGIN_TEST_SUITE_CEILING=0 PLUGIN_TEST_SUITE_EXCEPTIONS="$no_exceptions" \
  PLUGIN_TEST_SERIAL_LIST="$empty_list" run_runner 2 "a zero ceiling is rejected" --root "$r"
assert_output_has "the bad ceiling is named" "PLUGIN_TEST_SUITE_CEILING must be a positive integer (got '0')"

stale=0
while read -r line secs _ || [[ -n "$line" ]]; do
  [[ -n "$line" && "$line" != \#* ]] || continue
  if [[ ! -f "$ROOT/$line" || ! "$secs" =~ ^[1-9][0-9]*$ ]]; then
    fail "suite-budget-exceptions.txt row is not an existing suite and a ceiling: $line $secs"
    stale=1
  fi
done <"$ROOT/scripts/suite-budget-exceptions.txt"
((stale)) || ok "every suite-budget-exceptions.txt row names an existing suite and a ceiling"
for shipped_list in "$ROOT/scripts/run-plugin-tests-serial.txt" "$ROOT/scripts/run-plugin-tests-advisory.txt"; do
  stale=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ ! -f "$ROOT/$line" ]]; then
      fail "${shipped_list##*/} names a suite that does not exist: $line"
      stale=1
    fi
  done <"$shipped_list"
  ((stale)) || ok "every ${shipped_list##*/} entry names an existing suite"
done

test_harness::report
