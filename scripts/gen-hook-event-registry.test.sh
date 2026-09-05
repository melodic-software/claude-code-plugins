#!/usr/bin/env bash
# Unit tests for gen-hook-event-registry.sh. Builds a fixture tree per case
# (a plugins/claude-ops/hooks with a copy of the real hooks.json and the real
# session-log-lib.sh) and runs the generator against a saved copy of the
# Hooks reference lifecycle table, so nothing here touches the network.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/gen-hook-event-registry.sh"
TABLE="$SELF_DIR/fixtures/hooks-lifecycle-table.md"
REAL_HOOKS_JSON="$REPO/plugins/claude-ops/hooks/hooks.json"
LIB="$REPO/plugins/claude-ops/hooks/session-log-lib.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

FIXTURES=()
cleanup() {
  local d
  for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done
}
trap cleanup EXIT

# shellcheck disable=SC2016  # literal hooks.json command text, never expanded here
PRODUCER='"${CLAUDE_PLUGIN_ROOT}"/hooks/session-event-log.sh'
# shellcheck disable=SC2016
RETENTION='"${CLAUDE_PLUGIN_ROOT}"/hooks/session-retention.sh'

# new_fixture -> a repo root carrying the real hooks.json with every producer
# row stripped (so the base is the nine handlers alone) and the lib.
new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/plugins/claude-ops/hooks"
  jq --indent 2 --arg prod "$PRODUCER" --arg ret "$RETENTION" '
    .hooks |= (with_entries(.value |= map(select(any(.hooks[]?; .command == $prod or .command == $ret) | not)))
               | with_entries(select(.value | length > 0)))' "$REAL_HOOKS_JSON" >"$dir/plugins/claude-ops/hooks/hooks.json"
  cp "$LIB" "$dir/plugins/claude-ops/hooks/"
  FIXTURES+=("$dir")
  printf '%s' "$dir"
}

# --- a full run from the saved table -----------------------------------------
f="$(new_fixture)"
BASE_HANDLERS=$(jq -S '[.hooks[][] | .hooks[] | .command] | sort' "$f/plugins/claude-ops/hooks/hooks.json")
out=$(bash "$SCRIPT" --from "$TABLE" --root "$f" --as-of 2026-09-05 2>&1)
rc=$?
REG="$f/plugins/claude-ops/hooks/hook-events.registry.json"
HJ="$f/plugins/claude-ops/hooks/hooks.json"
if ((rc == 0)) && [[ -s "$REG" ]]; then
  ok "a run from the saved table writes the registry"
else
  fail "a run from the saved table writes the registry (rc=$rc): $out"
fi

n=$(jq length "$REG")
if ((n == 33)); then ok "33 events parsed from the table"; else fail "expected 33 events, got $n"; fi

incomplete=$(jq '[.[] | select((has("name") and has("when") and has("category") and has("producer") and has("claim") and has("basis") and has("as_of") and has("recheck")) | not)] | length' "$REG")
if [[ "$incomplete" == 0 ]]; then ok "every entry carries the four-part record plus category and producer"; else fail "$incomplete entries are incomplete"; fi

as_of=$(jq -r '[.[].as_of] | unique | join(",")' "$REG")
if [[ "$as_of" == "2026-09-05" ]]; then ok "as-of date stamped on every entry"; else fail "as_of: $as_of"; fi

if jq -e '[.[] | .recheck | test("changelog")] | all' "$REG" >/dev/null; then
  ok "every recheck trigger names an observable occasion"
else
  fail "a recheck trigger is not the changelog-ingest occasion"
fi

# The three behavior-changing events are excluded with a reason; the rest observe.
for ev in WorktreeCreate MessageDisplay FileChanged; do
  p=$(jq -r --arg e "$ev" '.[] | select(.name == $e) | .producer' "$REG")
  if [[ "$p" == exclude:* ]]; then ok "$ev is excluded ($p)"; else fail "$ev should be excluded, got: $p"; fi
  rows=$(jq -r --arg e "$ev" --arg prod "$PRODUCER" '[.hooks[$e][]? | .hooks[] | select(.command == $prod)] | length' "$HJ")
  if [[ "$rows" == 0 ]]; then ok "$ev has no producer row in hooks.json"; else fail "$ev has $rows producer rows"; fi
done
observed=$(jq '[.[] | select(.producer == "observe")] | length' "$REG")
if ((observed == 30)); then ok "30 events are observable"; else fail "expected 30 observable events, got $observed"; fi

# One producer row per observable event, with statusMessage and timeout.
missing=0
while IFS= read -r ev; do
  c=$(jq -r --arg e "$ev" --arg prod "$PRODUCER" '[.hooks[$e][]? | .hooks[] | select(.command == $prod and .timeout == 5 and (.statusMessage | length > 0))] | length' "$HJ")
  [[ "$c" == 1 ]] || missing=$((missing + 1))
done < <(jq -r '.[] | select(.producer == "observe") | .name' "$REG")
if ((missing == 0)); then ok "every observable event has exactly one producer row"; else fail "$missing observable events lack their producer row"; fi

ret=$(jq -r --arg ret "$RETENTION" '[.hooks.SessionEnd[]? | .hooks[] | select(.command == $ret)] | length' "$HJ")
if [[ "$ret" == 1 ]]; then ok "SessionEnd carries the retention row once"; else fail "retention rows on SessionEnd: $ret"; fi
ret_timeout=$(jq -r --arg ret "$RETENTION" '.hooks.SessionEnd[] | .hooks[] | select(.command == $ret) | has("timeout")' "$HJ")
if [[ "$ret_timeout" == false ]]; then ok "the retention row carries no timeout (a plugin timeout only lowers the cap)"; else fail "retention row has a timeout"; fi

# The nine existing handlers survive the merge, in order.
AFTER_HANDLERS=$(jq -S --arg prod "$PRODUCER" --arg ret "$RETENTION" '[.hooks[][] | .hooks[] | select(.command != $prod and .command != $ret) | .command] | sort' "$HJ")
if [[ "$BASE_HANDLERS" == "$AFTER_HANDLERS" ]]; then ok "the existing handlers survive the regeneration"; else fail "existing handlers changed"; fi
first_key=$(jq -r '.hooks | keys_unsorted[0]' "$HJ")
if [[ "$first_key" == StopFailure ]]; then ok "existing key order preserved (StopFailure first)"; else fail "first key is $first_key"; fi

# Idempotent: a second run changes nothing.
before=$(jq -S . "$HJ")
bash "$SCRIPT" --from "$TABLE" --root "$f" --as-of 2026-09-05 >/dev/null 2>&1
after=$(jq -S . "$HJ")
if [[ "$before" == "$after" ]]; then ok "a second run is idempotent"; else fail "a second run changed hooks.json"; fi

# --check passes on the generated tree and fails when a row is removed.
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 0)); then ok "--check is clean on a generated tree"; else fail "--check on a clean tree (rc=$rc): $out"; fi
jq --indent 2 '.hooks.PostToolUse |= .[:-1]' "$HJ" >"$HJ.drift" && mv "$HJ.drift" "$HJ"
out=$(bash "$SCRIPT" --check --root "$f" 2>&1)
rc=$?
if ((rc == 1)) && [[ "$out" == *drift* ]]; then ok "--check fails on a removed producer row"; else fail "--check on drift (rc=$rc): $out"; fi

# --- the category table agrees with session-log-lib.sh -------------------------
# shellcheck source=../plugins/claude-ops/hooks/session-log-lib.sh
source "$LIB"
disagree=0
while IFS=$'\t' read -r ev cat; do
  slog_category_to c "$ev"
  [[ "$c" == "$cat" ]] || {
    disagree=$((disagree + 1))
    echo "  $ev: registry=$cat lib=$c" >&2
  }
done < <(jq -r '.[] | [.name, .category] | @tsv' "$REG")
if ((disagree == 0)); then ok "registry categories agree with slog_category_to"; else fail "$disagree events disagree with slog_category_to"; fi

# --- the under-25-rows refusal ---------------------------------------------------
f="$(new_fixture)"
short="$(mktemp)"
FIXTURES+=("$short")
head -12 "$TABLE" >"$short"
out=$(bash "$SCRIPT" --from "$short" --root "$f" 2>&1)
rc=$?
if ((rc == 2)) && [[ ! -e "$f/plugins/claude-ops/hooks/hook-events.registry.json" ]]; then
  ok "fewer than 25 rows: exit 2 and nothing written"
else
  fail "short table (rc=$rc): $out"
fi

# --- an unknown event is excluded with a warning, never registered ------------------
f="$(new_fixture)"
odd="$(mktemp)"
FIXTURES+=("$odd")
{ cat "$TABLE"; } >"$odd"
# shellcheck disable=SC2016  # the backticks are markdown table text, not a substitution
sed 's/^| `SessionEnd`  *|/| `MysteryEvent`        |/' "$odd" >"$odd.2" && mv "$odd.2" "$odd"
out=$(bash "$SCRIPT" --from "$odd" --root "$f" 2>&1)
if [[ "$out" == *"WARN unknown event 'MysteryEvent'"* ]]; then ok "an unknown event warns"; else fail "no warning for an unknown event: $out"; fi
p=$(jq -r '.[] | select(.name == "MysteryEvent") | .producer' "$f/plugins/claude-ops/hooks/hook-events.registry.json")
if [[ "$p" == "exclude: unclassified"* ]]; then ok "an unknown event is excluded"; else fail "unknown event producer: $p"; fi
rows=$(jq -r --arg prod "$PRODUCER" '[.hooks.MysteryEvent[]? | .hooks[] | select(.command == $prod)] | length' "$f/plugins/claude-ops/hooks/hooks.json")
if [[ "$rows" == 0 ]]; then ok "an unknown event gets no row"; else fail "unknown event got $rows rows"; fi

test_harness::report
