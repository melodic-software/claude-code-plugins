#!/usr/bin/env bash
# Unit tests for test-plugin-mods.sh. Each case builds a synthetic plugins/
# tree, puts a stub `claude` (or none) first on a PATH that holds only the
# tools the script uses, and runs a copy of the script against the tree.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/test-plugin-mods.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""
NODE="$(command -v node)" || {
  echo "node not on PATH" >&2
  exit 2
}
BASH_BIN="$(command -v bash)"

# new_case: fresh fixture in $f with a bin/ dir holding node and dirname only.
new_case() {
  fixture_tree::build f --sut "$SCRIPT" --plugins
  mkdir -p "$f/bin"
  ln -s "$NODE" "$f/bin/node"
  ln -s "$(command -v dirname)" "$f/bin/dirname"
}

hooks_json() { # <plugin> <json>
  mkdir -p "$f/plugins/$1/hooks"
  printf '%s\n' "$2" >"$f/plugins/$1/hooks/hooks.json"
}

# stub_claude <version> <test-exit>: logs each `plugin test` dir to calls.log.
stub_claude() {
  cat >"$f/bin/claude" <<EOF
#!$BASH_BIN
if [[ "\$1" == --version ]]; then echo "$1 (Claude Code)"; exit 0; fi
if [[ "\$1 \$2" == "plugin test" ]]; then echo "\$3" >>"$f/calls.log"; exit $2; fi
exit 64
EOF
  chmod +x "$f/bin/claude"
}

no_test_ran() { # <name>
  if [[ -e "$f/calls.log" ]]; then
    bad "$1" "calls: $(cat "$f/calls.log")"
  else
    pass "$1"
  fi
}

run() { # <expected-exit> <name>
  LAST_OUTPUT="$(PATH="$f/bin" "$BASH_BIN" "$f/scripts/test-plugin-mods.sh" 2>&1)"
  local status=$?
  if [[ $status -eq $1 ]]; then
    pass "$2: exit $1"
  else
    bad "$2" "expected exit $1, got $status; output: $LAST_OUTPUT"
  fi
}

MOD='{"modules": ["./register.ts"]}'
CLASSIC='{"hooks": {"PreToolUse": []}}'

new_case
hooks_json classic "$CLASSIC"
hooks_json empty '{"modules": []}'
stub_claude 2.1.287 0
run 0 "no plugin ships a mod"
assert_output_contains "no-mod skip line" "skipped, no plugin ships a mod"
no_test_ran "no-mod runs no test"

new_case
hooks_json withmod "$MOD"
run 0 "claude absent"
assert_output_contains "claude-absent skip line" "skipped, claude CLI not on PATH (1 mod(s) untested)"

new_case
hooks_json withmod "$MOD"
stub_claude 2.1.286 0
run 0 "CLI older than mods"
assert_output_contains "old-CLI skip line" "skipped, claude 2.1.286 predates 2.1.287"
no_test_ran "old CLI runs no test"

new_case
hooks_json withmod "$MOD"
hooks_json classic "$CLASSIC"
stub_claude 2.1.300 0
run 0 "mod tests pass"
if [[ "$(cat "$f/calls.log" 2>/dev/null)" == "plugins/withmod" ]]; then
  pass "only the mod plugin is tested"
else
  bad "only the mod plugin is tested" "calls: $(cat "$f/calls.log" 2>/dev/null)"
fi

new_case
hooks_json withmod "$MOD"
stub_claude 2.1.287 0
rm "$f/bin/node"
run 2 "node absent is an error, not 'no mod'"
assert_output_contains "node-absent line" "node not on PATH"
no_test_ran "node absent runs no test"

new_case
hooks_json withmod "$MOD"
stub_claude 2.10.0 1
run 1 "a failing mod test fails the run"
assert_output_contains "failure line" "Mod tests failed."

test_harness::report
