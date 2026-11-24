#!/usr/bin/env bash
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

new_case() {
  fixture_tree::build f --sut "$SCRIPT" --plugins
  mkdir -p "$f/bin"
  ln -s "$NODE" "$f/bin/node"
  local tool
  for tool in dirname mktemp cat rm; do
    ln -s "$(command -v "$tool")" "$f/bin/$tool"
  done
}

manifest() {
  mkdir -p "$f/plugins/$1/.claude-plugin"
  printf '%s\n' "$2" >"$f/plugins/$1/.claude-plugin/plugin.json"
}

claude_floor() {
  printf '{"requires": [{"id": "claude", "detect": {"any": ["claude"]}}, {"id": "claude-mods", "detect": {"any": ["claude"], "version": {"min": "%s"}}}]}\n' "$2" >"$f/plugins/$1/prerequisites.json"
}

ENGINES='{"name": "p", "engines": {"claude-code": ">=2.1.287"}}'

hooks_json() {
  mkdir -p "$f/plugins/$1/hooks"
  printf '%s\n' "$2" >"$f/plugins/$1/hooks/hooks.json"
  manifest "$1" "$ENGINES"
}

stub_claude() {
  cat >"$f/bin/claude" <<EOF
#!$BASH_BIN
if [[ "\$1" == --version ]]; then echo "$1 (Claude Code)"; exit 0; fi
if [[ "\$1 \$2" == "plugin test" ]]; then
  echo "\$3" >>"$f/calls.log"
  echo "tested \$3"
  if [[ "\$3" == plugins/failing ]]; then echo "(fail) masks a token at 100% [12.50ms]" >&2; exit 1; fi
  exit $2
fi
exit 64
EOF
  chmod +x "$f/bin/claude"
}

no_test_ran() {
  if [[ -e "$f/calls.log" ]]; then
    bad "$1" "calls: $(cat "$f/calls.log")"
  else
    pass "$1"
  fi
}

run() {
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

new_case
hooks_json failing "$MOD"
hooks_json passing "$MOD"
stub_claude 2.1.300 0
run 1 "a failing mod fails the run when a later mod passes"
assert_output_contains "failure line beside a passing mod" "Mod tests failed."
assert_output_contains "a failing mod's annotation names the plugin and the failing test" \
  "::error title=Mod tests failed::plugins/failing: masks a token at 100%25"
assert_output_contains "the failure lists the failing plugins" "Failing mod plugins: plugins/failing"
expected=$'=== claude plugin test plugins/failing ===\ntested plugins/failing\n(fail) masks a token at 100% [12.50ms]\n::error title=Mod tests failed::plugins/failing: masks a token at 100%25\n=== claude plugin test plugins/passing ===\ntested plugins/passing'
if [[ "$LAST_OUTPUT" == "$expected"* ]]; then
  pass "each mod's output prints under its own header, in order"
else
  bad "each mod's output prints under its own header, in order" "output: $LAST_OUTPUT"
fi

stub_slow_claude() {
  cat >"$f/bin/claude" <<EOF
#!$BASH_BIN
if [[ "\$1" == --version ]]; then echo "2.1.300 (Claude Code)"; exit 0; fi
echo S >>"$f/spans.log"
$(command -v sleep) 0.3
echo E >>"$f/spans.log"
EOF
  chmod +x "$f/bin/claude"
}

max_concurrent() {
  local open=0 max=0 span
  while IFS= read -r span; do
    if [[ $span == S ]]; then ((++open > max)) && max=$open; else ((open--)); fi
  done <"$f/spans.log"
  echo "$max"
}

new_case
for p in a b c d e; do hooks_json "$p" "$MOD"; done
stub_slow_claude
run 0 "five mods under the default cap"
got="$(max_concurrent)"
if [[ $got == 2 ]]; then
  pass "at most 2 mods test at once by default"
else
  bad "at most 2 mods test at once by default" "max concurrent: $got"
fi
assert_output_contains "the last mod still prints under its header" "=== claude plugin test plugins/e ==="

new_case
for p in a b c; do hooks_json "$p" "$MOD"; done
stub_slow_claude
MOD_TEST_JOBS=1 run 0 "MOD_TEST_JOBS=1 runs the mods one at a time"
got="$(max_concurrent)"
if [[ $got == 1 ]]; then
  pass "MOD_TEST_JOBS=1 caps concurrency at 1"
else
  bad "MOD_TEST_JOBS=1 caps concurrency at 1" "max concurrent: $got"
fi

register_file() {
  mkdir -p "$f/plugins/$1/hooks"
  : >"$f/plugins/$1/hooks/$2"
}

new_case
hooks_json stray "$CLASSIC"
register_file stray register.ts
hooks_json withmod "$MOD"
register_file withmod register.tsx
stub_claude 2.1.300 0
run 1 "a register file with no modules fails the run"
assert_output_contains "no-modules line" "plugins/stray ships hooks/register.ts but hooks/hooks.json names no modules"
no_test_ran "a register file with no modules runs no test"

new_case
register_file nohooks register.tsx
run 1 "a register file with no hooks.json fails even without claude"
assert_output_contains "no-hooks.json line" "plugins/nohooks ships hooks/register.tsx but hooks/hooks.json names no modules"

new_case
hooks_json empty '{"modules": []}'
register_file empty register.ts
stub_claude 2.1.300 0
run 1 "a register file beside an empty modules array fails the run"
no_test_ran "an empty modules array runs no test"

new_case
hooks_json withmod "$MOD"
register_file withmod register.tsx
stub_claude 2.1.300 0
run 0 "a register file beside a modules array passes"

new_case
hooks_json bare "$MOD"
manifest bare '{"name": "bare"}'
hooks_json classic "$CLASSIC"
manifest classic '{"name": "classic"}'
stub_claude 2.1.300 0
run 1 "a mod with no engines range fails the run"
assert_output_contains "no-engines line" "plugins/bare ships a mod but declares no engines[\"claude-code\"] range"
no_test_ran "a mod with no engines range runs no test"

new_case
hooks_json drift "$MOD"
claude_floor drift 2.1.290
stub_claude 2.1.300 0
run 1 "an engines range other than the prerequisites floor fails the run"
assert_output_contains "drift line" "plugins/drift ships a mod but declares engines[\"claude-code\"] \">=2.1.287\", not \">=2.1.290\""

new_case
hooks_json matched "$MOD"
claude_floor matched 2.1.287
stub_claude 2.1.300 0
run 0 "an engines range equal to the prerequisites floor passes"

test_harness::report
