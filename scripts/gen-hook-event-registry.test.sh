#!/usr/bin/env bash
# Unit tests for gen-hook-event-registry.sh. Builds a fixture tree per case (a
# plugins/harness-ops/hooks with a copy of the real hooks.json seeded with
# stale event-log rows, the real session-log-lib.sh, and a register.ts whose
# generated block is stale) and runs the generator against a saved copy of the
# Hooks reference lifecycle table, so nothing here touches the network.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/gen-hook-event-registry.sh"
TABLE="$SELF_DIR/fixtures/hooks-lifecycle-table.md"
REAL_HOOKS_JSON="$REPO/plugins/harness-ops/hooks/hooks.json"
LIB="$REPO/plugins/harness-ops/hooks/session-log-lib.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder and slog_category_to assign through a nameref or printf -v, and
# the linter cannot follow either; declaring the out-vars here is what tells it
# (SC2154) the names are written.
f="" c=""

# The block the saved table must produce, written out by hand: the table's 33
# events minus the five the generator excludes (WorktreeCreate, MessageDisplay,
# FileChanged, PreToolUse, PostToolUse), in byte order, one hook per event.
EXPECTED_BLOCK="  on('classic.ConfigChange', record).catch(passThrough)
  on('classic.CwdChanged', record).catch(passThrough)
  on('classic.DirectoryAdded', record).catch(passThrough)
  on('classic.Elicitation', record).catch(passThrough)
  on('classic.ElicitationResult', record).catch(passThrough)
  on('classic.InstructionsLoaded', record).catch(passThrough)
  on('classic.Notification', record).catch(passThrough)
  on('classic.PermissionDenied', record).catch(passThrough)
  on('classic.PermissionRequest', record).catch(passThrough)
  on('classic.PostCompact', record).catch(passThrough)
  on('classic.PostModelSwitch', record).catch(passThrough)
  on('classic.PostToolBatch', record).catch(passThrough)
  on('classic.PostToolUseFailure', record).catch(passThrough)
  on('classic.PreCompact', record).catch(passThrough)
  on('classic.PreModelSwitch', record).catch(passThrough)
  on('classic.SessionEnd', record).catch(passThrough)
  on('classic.SessionStart', record).catch(passThrough)
  on('classic.Setup', record).catch(passThrough)
  on('classic.Stop', record).catch(passThrough)
  on('classic.StopFailure', record).catch(passThrough)
  on('classic.SubagentStart', record).catch(passThrough)
  on('classic.SubagentStop', record).catch(passThrough)
  on('classic.TaskCompleted', record).catch(passThrough)
  on('classic.TaskCreated', record).catch(passThrough)
  on('classic.TeammateIdle', record).catch(passThrough)
  on('classic.UserPromptExpansion', record).catch(passThrough)
  on('classic.UserPromptSubmit', record).catch(passThrough)
  on('classic.WorktreeRemove', record).catch(passThrough)"

MOD_HEAD="export const register = (on, options) => {
  if (options.session_event_log_enabled !== true) return
  // BEGIN GENERATED: observed events"
MOD_TAIL="  // END GENERATED: observed events
}
// sentinel: text after the block survives"

# A register.ts whose block is stale: an event the table does not carry, and
# one real event where 28 belong.
STALE_MOD="$MOD_HEAD
  on('classic.Bogus', record).catch(passThrough)
  on('classic.Stop', record).catch(passThrough)
$MOD_TAIL"

# new_fixture <out-var> [--no-mod] -> a repo root carrying the real hooks.json
# plus two event-log rows the generator must strip (an exec-form producer row
# on Stop, beside its own handler, and a bare-command retention row on a
# SessionEnd key that holds nothing else), the lib, and the stale register.ts.
new_fixture() {
  local dir
  fixture_tree::build "$1" --plugins || return 1
  dir="${!1}/plugins/harness-ops/hooks"
  mkdir -p "$dir"
  # shellcheck disable=SC2016  # literal hooks.json command text, never expanded here
  jq --indent 2 \
    --arg prod '${CLAUDE_PLUGIN_ROOT}/hooks/session-event-log.sh' \
    --arg launcher '${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs' \
    --arg ret 'bash "${CLAUDE_PLUGIN_ROOT}"/hooks/session-retention.sh' '
    .hooks.Stop += [{hooks: [{type: "command", command: "node", args: [$launcher, "--require-true", "SESSION_EVENT_LOG_ENABLED", $prod], timeout: 5}]}]
    | .hooks.SessionEnd = [{hooks: [{type: "command", command: $ret, shell: "bash"}]}]' \
    "$REAL_HOOKS_JSON" | tr -d '\r' >"$dir/hooks.json"
  cp "$LIB" "$dir/"
  [[ "${2:-}" == --no-mod ]] || printf '%s\n' "$STALE_MOD" >"$dir/register.ts"
}

block_of() { awk '/END GENERATED: observed events/ { f = 0 } f; /BEGIN GENERATED: observed events/ { f = 1 }' "$1"; }
hooks_of() { jq -S .hooks "$1" | tr -d '\r'; }
keys_of() { jq -c '.hooks | keys_unsorted' "$1" | tr -d '\r'; }
run_from() { bash "$SCRIPT" --from "$1" --root "$2" --as-of 2026-09-05 2>&1; }

# --- a full run from the saved table -----------------------------------------
new_fixture f
H="$f/plugins/harness-ops/hooks"
REG="$H/hook-events.registry.json"
out=$(run_from "$TABLE" "$f")
rc=$?
if ((rc == 0)) && [[ -s "$REG" ]]; then
  ok "a run from the saved table writes the registry"
else
  fail "a run from the saved table writes the registry (rc=$rc): $out"
fi

n=$(jq length "$REG")
if ((n == 33)); then ok "33 events parsed from the table"; else fail "expected 33 events, got $n"; fi

incomplete=$(jq '[.[] | select((has("name") and has("when") and has("category") and has("producer") and has("claim") and has("basis") and has("as_of") and has("recheck")) | not)] | length' "$REG")
if [[ "$incomplete" == 0 ]]; then ok "every entry carries the four-part record plus category and producer"; else fail "$incomplete entries are incomplete"; fi

as_of=$(jq -r '[.[].as_of] | unique | join(",")' "$REG" | tr -d '\r')
if [[ "$as_of" == "2026-09-05" ]]; then ok "as-of date stamped on every entry"; else fail "as_of: $as_of"; fi

if jq -e '[.[] | .recheck | test("changelog")] | all' "$REG" >/dev/null; then
  ok "every recheck trigger names an observable occasion"
else
  fail "a recheck trigger is not the changelog-ingest occasion"
fi

for ev in WorktreeCreate MessageDisplay FileChanged PreToolUse PostToolUse; do
  p=$(jq -r --arg e "$ev" '.[] | select(.name == $e) | .producer' "$REG" | tr -d '\r')
  if [[ "$p" == exclude:* ]]; then ok "$ev is excluded in the registry"; else fail "$ev should be excluded, got: $p"; fi
done

# The module: the block between the markers is exactly the hand-written one,
# and every line outside the markers is untouched.
block=$(block_of "$H/register.ts")
if [[ "$block" == "$EXPECTED_BLOCK" ]]; then
  ok "register.ts carries one classic hook per observable event, sorted"
else
  fail "generated block differs from the expected one: $(diff <(printf '%s\n' "$EXPECTED_BLOCK") <(printf '%s\n' "$block"))"
fi
if cmp -s "$H/register.ts" <(printf '%s\n%s\n%s\n' "$MOD_HEAD" "$EXPECTED_BLOCK" "$MOD_TAIL"); then
  ok "register.ts outside the markers is preserved byte for byte"
else
  fail "register.ts outside the markers changed"
fi

# hooks.json: the seeded event-log rows are gone and nothing else moved. The
# real hooks.json carries no event-log row (ADR 0056), so it is the oracle.
if [[ "$(hooks_of "$H/hooks.json")" == "$(hooks_of "$REAL_HOOKS_JSON")" ]]; then
  ok "hooks.json keeps no event-log or retention row and every other handler"
else
  fail "hooks.json after a run: $(diff <(hooks_of "$REAL_HOOKS_JSON") <(hooks_of "$H/hooks.json"))"
fi
if [[ "$(keys_of "$H/hooks.json")" == "$(keys_of "$REAL_HOOKS_JSON")" ]]; then
  ok "hooks.json key order preserved"
else
  fail "hooks.json keys: $(keys_of "$H/hooks.json")"
fi

# Idempotent: a second run leaves all three files byte-identical.
mkdir -p "$f/run1"
cp "$REG" "$H/register.ts" "$H/hooks.json" "$f/run1/"
run_from "$TABLE" "$f" >/dev/null
same=0
for file in hook-events.registry.json register.ts hooks.json; do
  if cmp -s "$f/run1/$file" "$H/$file"; then same=$((same + 1)); else fail "a second run changed $file"; fi
done
((same == 3)) && ok "a second run is byte-identical on the registry, register.ts and hooks.json"

# --check: clean on a generated tree; fails on a stale block, an event-log row,
# or a lost marker, each for its own reason.
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 0)); then ok "--check is clean on a generated tree"; else fail "--check on a clean tree (rc=$rc): $out"; fi

grep -v "classic.Stop'" "$f/run1/register.ts" >"$H/register.ts"
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 1)) && [[ "$out" == *"drift from the registry"* ]]; then ok "--check fails on a stale block"; else fail "--check on a stale block (rc=$rc): $out"; fi
cp "$f/run1/register.ts" "$H/register.ts"

# shellcheck disable=SC2016  # literal hooks.json command text
jq --indent 2 --arg prod '${CLAUDE_PLUGIN_ROOT}/hooks/session-event-log.sh' \
  '.hooks.Stop += [{hooks: [{type: "command", command: "node", args: [$prod]}]}]' \
  "$f/run1/hooks.json" | tr -d '\r' >"$H/hooks.json"
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 1)) && [[ "$out" == *"carries an event-log"* ]]; then ok "--check fails on an event-log row in hooks.json"; else fail "--check on a row (rc=$rc): $out"; fi
cp "$f/run1/hooks.json" "$H/hooks.json"

grep -v "END GENERATED" "$f/run1/register.ts" >"$H/register.ts"
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 1)) && [[ "$out" == *"lacks the BEGIN/END"* ]]; then ok "--check fails on a lost marker"; else fail "--check on a lost marker (rc=$rc): $out"; fi

# --- the category table agrees with session-log-lib.sh -------------------------
# shellcheck source=../plugins/harness-ops/hooks/session-log-lib.sh
source "$LIB"
disagree=0 seen=0
while IFS=$'\t' read -r ev cat; do
  seen=$((seen + 1))
  slog_category_to c "$ev"
  [[ "$c" == "$cat" ]] || {
    disagree=$((disagree + 1))
    echo "  $ev: registry=$cat lib=$c" >&2
  }
done < <(jq -r '.[] | [.name, .category] | @tsv' "$REG" | tr -d '\r')
if ((seen == 33 && disagree == 0)); then
  ok "registry categories agree with slog_category_to"
else
  fail "$disagree of $seen events disagree with slog_category_to"
fi

# --- a missing register.ts or marker fails, writing nothing ----------------------
for variant in missing unmarked; do
  if [[ "$variant" == missing ]]; then
    new_fixture f --no-mod
  else
    new_fixture f
    grep -v "BEGIN GENERATED" <<<"$STALE_MOD" >"$f/plugins/harness-ops/hooks/register.ts"
  fi
  H="$f/plugins/harness-ops/hooks"
  cp "$H/hooks.json" "$f/hooks.before"
  out=$(run_from "$TABLE" "$f")
  rc=$?
  if ((rc == 1)) && [[ "$out" == *"lacks the BEGIN/END"* ]] && [[ ! -e "$H/hook-events.registry.json" ]] && cmp -s "$f/hooks.before" "$H/hooks.json"; then
    ok "register.ts $variant: exit 1 and nothing written"
  else
    fail "register.ts $variant (rc=$rc): $out"
  fi
done

# --- the under-25-rows refusal ---------------------------------------------------
new_fixture f
H="$f/plugins/harness-ops/hooks"
head -12 "$TABLE" >"$f/short.md"
out=$(run_from "$f/short.md" "$f")
rc=$?
if ((rc == 2)) && [[ ! -e "$H/hook-events.registry.json" ]] && [[ "$(cat "$H/register.ts")" == "$STALE_MOD" ]]; then
  ok "fewer than 25 rows: exit 2 and nothing written"
else
  fail "short table (rc=$rc): $out"
fi

# --- an unknown event is excluded with a warning, never hooked ----------------------
new_fixture f
H="$f/plugins/harness-ops/hooks"
# shellcheck disable=SC2016  # the backticks are markdown table text, not a substitution
sed 's/^| `SessionEnd`  *|/| `MysteryEvent`        |/' "$TABLE" >"$f/odd.md"
out=$(run_from "$f/odd.md" "$f")
if [[ "$out" == *"WARN unknown event 'MysteryEvent'"* ]]; then ok "an unknown event warns"; else fail "no warning for an unknown event: $out"; fi
p=$(jq -r '.[] | select(.name == "MysteryEvent") | .producer' "$H/hook-events.registry.json" | tr -d '\r')
if [[ "$p" == "exclude: unclassified"* ]]; then ok "an unknown event is excluded"; else fail "unknown event producer: $p"; fi
block=$(block_of "$H/register.ts")
if [[ "$block" == "$(grep -v "classic.SessionEnd'" <<<"$EXPECTED_BLOCK")" ]]; then
  ok "an unknown event gets no hook in register.ts"
else
  fail "block with an unknown event: $block"
fi

test_harness::report
