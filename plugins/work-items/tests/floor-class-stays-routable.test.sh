#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture bodies are literal prose in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SKILL="$PLUGIN_ROOT/skills/attend-queue/SKILL.md"

PASS=0
FAIL=0
ok() {
  printf 'PASS: %s\n' "$1"
  PASS=$((PASS + 1))
}
fail() {
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
  FAIL=$((FAIL + 1))
}

transition_region() {
  awk '
    /^- \*\*Flip to agent-ready\./ { inside = 1 }
    inside && /^[[:space:]]*$/     { exit }
    inside                         { print }
  ' "$1"
}

# Verdict for one file: prints the first unmet requirement, or nothing when the
# region satisfies all three. Empty output means floor-aware.
transition_gap() {
  local region
  region="$(transition_region "$1")"
  if [[ -z "$region" ]]; then
    printf 'no "Flip to agent-ready" bullet found'
    return
  fi
  if grep -qF 'work-class: structural' <<<"$region"; then
    printf 'transition still names work-class: structural'
    return
  fi
  if ! grep -qF 'provenance: untrusted' <<<"$region"; then
    printf 'transition does not name provenance: untrusted'
    return
  fi
  if ! grep -qiE 'reclassif' <<<"$region"; then
    printf 'transition offers no reclassify branch'
    return
  fi
}

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

assert_flags() {
  local label="$1" body="$2" file gap
  file="$fixture_dir/$(printf '%s' "$label" | tr -c 'a-z0-9' '-').md"
  printf '%s\n' "$body" >"$file"
  gap="$(transition_gap "$file")"
  if [[ -n "$gap" ]]; then
    ok "detector flags $label"
  else
    fail "detector flags $label" "fixture passed the guard it should fail"
  fi
}

assert_accepts() {
  local label="$1" body="$2" file gap
  file="$fixture_dir/clean-$(printf '%s' "$label" | tr -c 'a-z0-9' '-').md"
  printf '%s\n' "$body" >"$file"
  gap="$(transition_gap "$file")"
  if [[ -z "$gap" ]]; then
    ok "detector accepts $label"
  else
    fail "detector accepts $label" "$gap"
  fi
}

assert_flags 'the unconditional pre-fix flip' \
  '- **Flip to agent-ready.** When an answer or ratification removes the human blocker, apply the
  autonomous-eligible role label and remove the human-gated role label **in the same edit** (both
  resolved from `config.role_labels`, never literals), an item wearing both roles is a
  contradiction. The item re-enters the worker loop'"'"'s frontier on its next cycle; do not dispatch
  it from this lane.

Next section.'

assert_flags 'a file with no flip transition at all' \
  '- **`[held]` rows**. Restate the brief and leave the next step to the operator.'

assert_flags 'floor classes named outside the transition' \
  '- **Flip to agent-ready.** Apply the autonomous-eligible role label and remove the human-gated
  role label in the same edit.

`provenance: untrusted` is human-gated; reclassify it.'

assert_flags 'a transition naming untrusted provenance with no reclassify branch' \
  '- **Flip to agent-ready.** Apply the autonomous-eligible role label unless the item carries
  `provenance: untrusted`, in which case leave the human-gated role label in place.'

assert_flags 'a transition that still gates on work-class: structural' \
  '- **Flip to agent-ready.** Apply the autonomous-eligible role label and remove the human-gated
  role label in the same edit.
- **Human-floor work class.** `work-class: structural` (C4) and `provenance: untrusted`
  (C5) stay human-gated: reclassify to C1-C3 in the same edit as the flip, or leave the
  human-gated role label in place so the attended view keeps listing the item.'

assert_accepts 'a floor-aware two-branch transition' \
  '- **Flip to agent-ready.** Apply the autonomous-eligible role label and remove the human-gated
  role label in the same edit. Only untrusted provenance blocks it.
- **Untrusted provenance.** `provenance: untrusted` (C5) stays human-gated: reclassify
  it in the same edit as the flip, or leave the human-gated role label in place so the attended
  view keeps listing the item.'

if [[ ! -f "$SKILL" ]]; then
  fail "attend-queue SKILL.md is present" "not found at $SKILL"
else
  gap="$(transition_gap "$SKILL")"
  if [[ -z "$gap" ]]; then
    ok "attend-queue flip transition is human-floor aware"
  else
    fail "attend-queue flip transition is human-floor aware" "$gap"
  fi
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
