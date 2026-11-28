#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/enumerate-all-projects.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

run_isolated() { env -u CLAUDE_CONFIG_DIR HOME="$1" bash "$SCRIPT"; }


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"


H2="$TEST_TMPDIR/h2"
mkdir -p "$H2"
rc=0
OUT=$(run_isolated "$H2") || rc=$?
assert_exit "missing projects root exits 0" 0 "$rc"
assert_contains "missing projects root reported" "$OUT" "No projects directory"


H3="$TEST_TMPDIR/h3"
M3A="$H3/.claude/projects/C--proj-alpha/memory"
M3B="$H3/.claude/projects/C--proj-beta/memory"
mkdir -p "$M3A" "$M3B"
printf '# Index\n- one\n- two\n' >"$M3A/MEMORY.md"
printf 'topic\n' >"$M3A/debugging.md"
printf '# Index\n- one\n' >"$M3B/MEMORY.md"
rc=0
OUT=$(run_isolated "$H3") || rc=$?
assert_exit "listing exits 0" 0 "$rc"
assert_contains "alpha dir listed" "$OUT" "C--proj-alpha/memory"
assert_contains "beta dir listed" "$OUT" "C--proj-beta/memory"
assert_contains "alpha MEMORY.md line count" "$OUT" "MEMORY.md:3"
assert_contains "alpha topic count" "$OUT" "topics:1"
assert_contains "beta topic count" "$OUT" "topics:0"


H4="$TEST_TMPDIR/h4"
M4="$H4/.claude/projects/C--proj-gamma/memory"
mkdir -p "$M4"
printf 'loose\n' >"$M4/loose.md"
rc=0
OUT=$(run_isolated "$H4" 2>&1) || rc=$?
assert_exit "no-MEMORY.md store exits 0" 0 "$rc"
assert_not_contains "no shell error leaks for a missing MEMORY.md" "$OUT" "No such file"
assert_contains "gamma dir listed" "$OUT" "C--proj-gamma/memory"
assert_contains "gamma MEMORY.md absent" "$OUT" "MEMORY.md:absent"
assert_contains "gamma topic count" "$OUT" "topics:1"


H5="$TEST_TMPDIR/h5"
mkdir -p "$H5/.claude/projects/C--proj-empty"
rc=0
OUT=$(run_isolated "$H5") || rc=$?
assert_exit "no memory dirs exits 0" 0 "$rc"
assert_contains "no memory dirs reported" "$OUT" "No per-project memory directories"


CFG="$TEST_TMPDIR/cfg"
M6="$CFG/projects/C--proj-relocated/memory"
mkdir -p "$M6"
printf '# Index\n' >"$M6/MEMORY.md"
H6="$TEST_TMPDIR/h6"
mkdir -p "$H6"
OUT=$(HOME="$H6" CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT")
assert_contains "relocated store listed" "$OUT" "C--proj-relocated/memory"
assert_not_contains "HOME tree not scanned when relocated" "$OUT" "$H6/.claude"

report_and_exit
