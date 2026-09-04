#!/usr/bin/env bash
# Unit tests for check-killswitch-hoist.sh. Builds a tiny synthetic plugins/ tree
# per scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it scans <fixture>/plugins/.
#
# The load-bearing case is "reversed order fails". A gate that only ever sees
# correct input proves nothing, so every rule below is exercised from BOTH sides.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-killswitch-hoist.sh"
HOOK_UTILS="$SELF_DIR/../lib/hook-utils.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

FIXTURES=()
cleanup() {
  local d
  for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done
}
trap cleanup EXIT

# The gate pins its inlined predicate against the real hook::is_enabled, so every
# fixture carries the real library rather than a stub: a stub would let the pin
# pass on text this repo does not actually ship.
new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins" "$dir/lib"
  cp "$SCRIPT" "$dir/scripts/check-killswitch-hoist.sh"
  cp "$HOOK_UTILS" "$dir/lib/hook-utils.sh"
  chmod +x "$dir/scripts/check-killswitch-hoist.sh"
  FIXTURES+=("$dir")
  printf '%s' "$dir"
}

# guard <fixture> <plugin> <name> <body>
guard() {
  local fixture="$1" plugin="$2" name="$3" body="$4"
  mkdir -p "$fixture/plugins/$plugin/hooks"
  printf '%s\n' "$body" >"$fixture/plugins/$plugin/hooks/$name"
}

# hooks_json <fixture> <plugin> <command>
hooks_json() {
  local fixture="$1" plugin="$2" command="$3"
  mkdir -p "$fixture/plugins/$plugin/hooks"
  jq -n --arg c "$command" \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' \
    >"$fixture/plugins/$plugin/hooks/hooks.json"
}

run_check() (
  cd "$1" && bash scripts/check-killswitch-hoist.sh 2>&1
)

HOISTED='#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

exit 0'

# The pre-#3719 shape, verbatim: library first, switch second.
REVERSED='#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "true" ]] || exit 0

exit 0'

LEGACY_CALL='#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "DEMO_GUARD"

exit 0'

NO_SWITCH='#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

exit 0'

# --- the rule, from both sides ----------------------------------------------

f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$HOISTED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "a hoisted guard passes"
else
  fail "a hoisted guard passes (rc=$rc): $out"
fi

f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$REVERSED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"BELOW the source"* ]]; then
  ok "a guard that reverses the order FAILS"
else
  fail "a guard that reverses the order FAILS (rc=$rc): $out"
fi

f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$LEGACY_CALL"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"hook::check_enabled"* ]]; then
  ok "a guard still calling hook::check_enabled FAILS"
else
  fail "a guard still calling hook::check_enabled FAILS (rc=$rc): $out"
fi

f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$NO_SWITCH"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"no inlined kill switch"* ]]; then
  ok "a guard with no kill switch at all FAILS"
else
  fail "a guard with no kill switch at all FAILS (rc=$rc): $out"
fi

# --- accepted shapes ---------------------------------------------------------

f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "${HOISTED/:-true\}\" == \"true\"/:-false\}\" == \"true\"}"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "an opt-in guard (unset default false) passes"
else
  fail "an opt-in guard (unset default false) passes (rc=$rc): $out"
fi

# The strict-and-loud shape: only the DISABLED arm is hoisted, because the
# "neither true nor false" arm speaks through a library function.
STRICT_LOUD='#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "false" ]] && exit 0

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

exit 0'
f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$STRICT_LOUD"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "a strict-and-loud guard hoisting only its disabled arm passes"
else
  fail "a strict-and-loud guard hoisting only its disabled arm passes (rc=$rc): $out"
fi

# A guard that sources nothing has no ordering to get wrong, but still needs the
# switch: the rule is "before any source", not "only when there is one".
NO_SOURCE='#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_DEMO_GUARD_ENABLED:-true}" == "true" ]] || exit 0

exit 0'
f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$NO_SOURCE"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "a guard that sources nothing passes on its switch alone"
else
  fail "a guard that sources nothing passes on its switch alone (rc=$rc): $out"
fi

# --- discovery ---------------------------------------------------------------

# Launcher arguments are guards; the launcher itself is not.
f="$(new_fixture)"
guard "$f" demo "run-guards.sh" '#!/usr/bin/env bash
exit 0'
guard "$f" demo "alpha.sh" "$HOISTED"
guard "$f" demo "beta.sh" "$REVERSED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/run-guards.sh alpha.sh beta.sh'
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"beta.sh"* && "$out" != *"run-guards.sh — no inlined"* ]]; then
  ok "run-guards.sh arguments are scanned and the launcher itself is not"
else
  fail "run-guards.sh arguments are scanned and the launcher itself is not (rc=$rc): $out"
fi

# A `--lib` value is a bundled classifier, not a guard.
f="$(new_fixture)"
guard "$f" demo "run-guards.sh" '#!/usr/bin/env bash
exit 0'
guard "$f" demo "alpha.sh" "$HOISTED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/run-guards.sh --lib lib/powershell/ps-command.sh alpha.sh'
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "a --lib value is not treated as a guard"
else
  fail "a --lib value is not treated as a guard (rc=$rc): $out"
fi

# A non-shell PreToolUse handler is REPORTED, not silently passed.
f="$(new_fixture)"
guard "$f" demo "alpha.sh" "$HOISTED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/alpha.sh'
mkdir -p "$f/plugins/pynode/hooks"
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"node"}]}]}}' \
  >"$f/plugins/pynode/hooks/hooks.json"
out="$(run_check "$f")"
rc=$?
if ((rc == 0)) && [[ "$out" == *"NOT SCANNED"* && "$out" == *"pynode"* ]]; then
  ok "a non-shell PreToolUse handler is reported as NOT SCANNED"
else
  fail "a non-shell PreToolUse handler is reported as NOT SCANNED (rc=$rc): $out"
fi

# A PostToolUse guard is out of scope and is not scanned.
f="$(new_fixture)"
guard "$f" demo "alpha.sh" "$HOISTED"
guard "$f" demo "post.sh" "$REVERSED"
mkdir -p "$f/plugins/demo/hooks"
jq -n '{hooks:{
  PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/alpha.sh"}]}],
  PostToolUse:[{matcher:"Write",hooks:[{type:"command",command:"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/post.sh"}]}]
}}' >"$f/plugins/demo/hooks/hooks.json"
out="$(run_check "$f")"
rc=$?
if ((rc == 0)); then
  ok "a PostToolUse guard is out of scope"
else
  fail "a PostToolUse guard is out of scope (rc=$rc): $out"
fi

# --- fail closed -------------------------------------------------------------

# No PreToolUse shell guard anywhere is an environment problem, not a clean run:
# a discovery bug must not read as "nothing to check".
f="$(new_fixture)"
mkdir -p "$f/plugins/empty/hooks"
jq -n '{hooks:{}}' >"$f/plugins/empty/hooks/hooks.json"
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"refusing to report clean"* ]]; then
  ok "finding no PreToolUse shell guard fails closed"
else
  fail "finding no PreToolUse shell guard fails closed (rc=$rc): $out"
fi

# A guard registered on PreToolUse but absent from the tree is a violation, not
# a skip.
f="$(new_fixture)"
guard "$f" demo "alpha.sh" "$HOISTED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/ghost.sh'
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"missing from the tree"* ]]; then
  ok "a registered but missing guard is a violation"
else
  fail "a registered but missing guard is a violation (rc=$rc): $out"
fi

# The semantic pin: if hook::is_enabled stops reading the env var the inlined
# copies reproduce, the gate stops rather than clearing fifteen stale copies.
f="$(new_fixture)"
guard "$f" demo "demo-guard.sh" "$HOISTED"
hooks_json "$f" demo '"${CLAUDE_PLUGIN_ROOT}"/hooks/demo-guard.sh'
sed -i 's/CLAUDE_PLUGIN_OPTION_${1}_ENABLED/CLAUDE_PLUGIN_OPTION_${1}_ACTIVE/' "$f/lib/hook-utils.sh"
out="$(run_check "$f")"
rc=$?
if ((rc != 0)) && [[ "$out" == *"no longer reads"* ]]; then
  ok "a changed hook::is_enabled trips the semantic pin"
else
  fail "a changed hook::is_enabled trips the semantic pin (rc=$rc): $out"
fi

test_harness::report
