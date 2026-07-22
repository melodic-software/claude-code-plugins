#!/usr/bin/env bash
# Cross-hook contract test: every guardrails hook's hook::require_jq call must
# use a hook-specific notice_once key, not a key shared across the plugin.
#
# Repro-first regression for a real bug (found in independent review of #836's
# fleet-adoption PR): all 9 jq-missing conversions initially passed the
# literal plugin id "guardrails" as require_jq's second argument. Since
# require_jq's notice_once key is "${plugin}-jq" (lib/hook-utils.sh), all 9
# resolved to the SAME key ("guardrails-jq") and therefore the SAME marker
# file within one session — whichever guard ran first silenced the other 8
# for the rest of the session, on both channels. No single-hook *.test.sh
# catches this: each isolates its own CLAUDE_PLUGIN_DATA/session, so two
# different guardrails hooks sharing one session (the real-world condition)
# is never exercised. This test simulates exactly that.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Every hook whose source CALLS hook::require_jq — discovered, not
# hand-enumerated, so a future 10th jq-consuming hook is covered automatically.
# Excludes hook-utils.sh (the function's own definition, not a call site) and
# *.test.sh (which reference the name in assertions/comments, not calls) —
# same exclusion shape as scripts/check-silent-skips.sh.
mapfile -t JQ_HOOKS < <(
  for f in "$HOOK_DIR"/*.sh; do
    base="${f##*/}"
    case "$base" in
    hook-utils.sh | *.test.sh) continue ;;
    *) ;;
    esac
    grep -l 'hook::require_jq' "$f" 2>/dev/null || true
  done | sort
)

if ((${#JQ_HOOKS[@]} < 2)); then
  bad "expected at least 2 guardrails hooks calling hook::require_jq, found ${#JQ_HOOKS[@]} — this test needs >=2 to prove cross-hook isolation"
fi

# --- Every hook's require_jq key is unique -----------------------------------
# Portable extraction (bash regex, not `grep -P` — BSD grep on macOS has no
# Perl-regex support, and this fleet targets Windows/macOS/Linux).
declare -A seen_keys=()
dup_found=0
for h in "${JQ_HOOKS[@]}"; do
  key=""
  while IFS= read -r line; do
    if [[ "$line" =~ hook::require_jq[[:space:]]+\"[^\"]*\"[[:space:]]+\"([^\"]+)\" ]]; then
      key="${BASH_REMATCH[1]}"
      break
    fi
  done <"$h"
  if [[ -z "$key" ]]; then
    bad "$(basename "$h"): could not extract require_jq's plugin argument"
    continue
  fi
  if [[ -n "${seen_keys[$key]:-}" ]]; then
    bad "duplicate require_jq key '$key': $(basename "$h") collides with ${seen_keys[$key]}"
    dup_found=1
  else
    seen_keys[$key]="$(basename "$h")"
  fi
done
((dup_found == 0)) && ok "every guardrails hook's require_jq key is unique (${#seen_keys[@]} distinct keys for ${#JQ_HOOKS[@]} hooks)"

# --- Runtime proof: hook::notice_once fires independently for each hook's
# ACTUAL extracted key, within one shared session/data-dir -------------------
# Real jq-removal is not portably simulable (isolated bin dir without jq
# cannot host bash + coreutils across Git Bash and Linux — same constraint
# secret-pattern-detection.test.sh documents), and require_jq short-circuits
# before ever calling notice_once when jq IS present (the normal test
# environment). So this drives hook::notice_once directly with each hook's
# real extracted key — the exact mechanism the bug lives in — rather than
# trying to force the jq-absent branch end-to-end.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
DATA_DIR="$TEST_TMPDIR/plugin-data"
mkdir -p "$DATA_DIR"
SESSION_INPUT='{"session_id":"cross-hook-test-session"}'

fired_count=0
(
  export CLAUDE_PLUGIN_DATA="$DATA_DIR"
  for key in "${!seen_keys[@]}"; do
    if hook::notice_once "${key}-jq" "$SESSION_INPUT"; then
      echo "FIRED:$key"
    fi
  done
) >"$TEST_TMPDIR/fire-log"
fired_count=$(grep -c '^FIRED:' "$TEST_TMPDIR/fire-log" 2>/dev/null || echo 0)

if ((fired_count == ${#seen_keys[@]})); then
  ok "hook::notice_once fired independently for all ${#seen_keys[@]} guardrails hook keys within one shared session/data-dir"
else
  bad "only $fired_count of ${#seen_keys[@]} guardrails hook keys fired independently — cross-hook notice_once key collision (or another regression). Fire log: $(cat "$TEST_TMPDIR/fire-log" 2>/dev/null)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
((FAIL == 0))
