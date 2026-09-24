#!/usr/bin/env bash
# Contract test for hook-census.sh: builds a throwaway plugins/fx/hooks/hooks.json,
# runs the census against its rows, and asserts on the counts and exit codes.
# The counts are the kernel's (strace), so this suite needs strace and fails
# closed without it: a census suite that skips proves nothing about the census
# the ratchet step runs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

if ! strace -qq -o /dev/null -e trace=execve true >/dev/null 2>&1; then
  fail "strace is missing or cannot trace here; hook-census.sh cannot be exercised"
  test_harness::report
  exit
fi

TMP=""
fixture_tree::build TMP --sut "$SCRIPT_DIR/hook-census.sh" --plugins --label hook-census
mkdir -p "$TMP/plugins/fx/hooks"
# Rows: a no-op, one that forks and execs once, a whole-file transcript read, a
# bounded one, and one that fails.
cat >"$TMP/plugins/fx/hooks/hooks.json" <<'JSON'
{"hooks": {
  "Stop": [{"hooks": [
    {"type": "command", "command": "exit 0 # noop"},
    {"type": "command", "command": "x=$(date); echo \"one fork $x\" >/dev/null # onefork"},
    {"type": "command", "command": "t=$(jq -r .transcript_path); cat \"$t\" >/dev/null # whole"},
    {"type": "command", "command": "t=$(jq -r .transcript_path); tail -c 100 \"$t\" >/dev/null # bounded"},
    {"type": "command", "command": "exit 1 # fails"},
    {"type": "command", "command": "echo marker # speaks"},
    {"type": "command", "command": "test \"$CENSUS_FX\" = on # envrow"},
    {"type": "command", "command": "s=\"$CLAUDE_PLUGIN_DATA/seen\"; [ -e \"$s\" ] && exit 0; : >\"$s\"; x=$(date) # warms"}
  ]}]
}}
JSON
CENSUS="$TMP/scripts/hook-census.sh"
PAYLOAD='{"session_id":"t","transcript_path":"@TRANSCRIPT@","hook_event_name":"Stop","cwd":"@DIR@"}'

census() { # <row> [options...]: sets OUT and RC
  local row="$1"
  shift
  OUT="$(bash "$CENSUS" fx Stop "$row" "$PAYLOAD" "$@" 2>&1)"
  RC=$?
}
expect() { # <name> <rc> <output substring>
  if [[ "$RC" == "$2" && "$OUT" == *"$3"* ]]; then
    pass "$1"
  else
    bad "$1" "expected rc $2 and '$3'; got rc $RC: $OUT"
  fi
}

census '# noop'
expect "a no-op row costs only its own sh" 0 "spawns=1 creations=0 execs=1"
census '# onefork'
expect "a substitution running date is one fork and one exec more" 0 "spawns=3 creations=1 execs=2"

census '# whole' --measure transcript-bytes --transcript-bytes 51200
case "$OUT" in
bytes=5[0-9][0-9][0-9][0-9]) pass "a whole-file read counts every transcript byte" ;;
*) bad "a whole-file read counts every transcript byte" "$OUT" ;;
esac
census '# whole' --measure growth
case "$OUT" in
growth=[1-9]*) pass "a whole-file read grows with the transcript" ;;
*) bad "a whole-file read grows with the transcript" "$OUT" ;;
esac
census '# bounded' --measure growth
expect "a bounded read is flat" 0 "growth=0 small=100 large=100"
census '# noop' --measure growth
expect "a row that never reads the transcript cannot pass as flat" 3 "no transcript byte was read"

# shellcheck disable=SC2016 # HOOK_STDOUT expands in the census's check shell
census '# speaks' --check 'grep -q marker "$HOOK_STDOUT"'
expect "--check sees the fire's stdout" 0 "spawns="
# shellcheck disable=SC2016
census '# noop' --check 'test -s "$HOOK_STDOUT"'
expect "a failing --check exits 3" 3 "--check failed"
census '# fails'
expect "a fire that exits nonzero exits 3" 3 "the fire exited 1"
census '# envrow'
expect "a fire without the row's variable fails" 3 "the fire exited 1"
census '# envrow' --env CENSUS_FX=on
expect "--env reaches the fire" 0 "spawns=1 creations=0 execs=1"
census '# warms'
expect "an unseeded fire takes the cold path" 0 "spawns=3 creations=1 execs=2"
census '# warms' --seed
expect "--seed measures the warm path" 0 "spawns=1 creations=0 execs=1"
census '# noop' --setup 'exit 1'
expect "a failing --setup exits 2" 2 "--setup failed"
census '# absent'
expect "a row no handler carries exits 2" 2 "no Stop handler"
census '# noop' --measure duration
expect "an unknown measure exits 2" 2 "hook-census.sh"

test_harness::report
