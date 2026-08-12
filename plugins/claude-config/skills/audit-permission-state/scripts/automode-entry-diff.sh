#!/usr/bin/env bash
# automode-entry-diff.sh — what entering auto mode does to the effective allow
# set, per rule, with the drop reason named.
#
# "On entering auto mode, broad allow rules that grant arbitrary code execution
# are dropped: Blanket Bash(*) or PowerShell(*); Wildcarded interpreters like
# Bash(python*); Package-manager run commands; Agent allow rules. Narrow rules
# like Bash(npm test) carry over." This script classifies every effective allow
# rule from the merge into exactly one of those documented classes or `kept`,
# using the same shared vocabulary (lib/permission-patterns.sh) that
# audit-permission-grants check P1 scans with — one definition, two consumers.
#
# `autoMode.classifyAllShell` inverts the carry-over answer wholesale: when
# true it "suspend[s] every Bash and PowerShell allow rule while auto mode is
# active", so narrow rules do NOT carry over. The classifier reads `autoMode`
# from user settings, managed settings, and inline --settings/SDK JSON only —
# never project or local settings — so this script resolves the key from the
# managed and user conf records alone and says so when a non-read scope sets it.
#
# Input: permission-merge.sh output on stdin (records pass through above the
# diff section unless --diff-only). With no piped input the sibling pipeline is
# run directly and its exit status is propagated.
#
# Output (diff section):
#   DIFF-NOTE: <text>                                    classifyAllShell state, bounds
#   entry-diff dropped class=<class> scopes=<a,b> <rule> one per dropped allow rule
#   entry-diff suspended reason=classifyAllShell scopes=<a,b> <rule>
#   entry-diff kept scopes=<a,b> <rule>                  one per carried-over allow rule
#   entry-diff summary allow_before=<n> dropped=<n> suspended=<n> kept=<n>
#
#   class  blanket | interpreter-wildcard | package-manager-run | agent
#          (the documented four; the vocabulary's script-glob alternative is an
#          interpreter-wildcard shape and reports as that class)
#
# Only allow rules change on entry: deny and ask rules are evaluated before the
# classifier in every mode and are not part of this diff.
#
# --oracle (opt-in, explicitly priced): cross-check the prediction against the
# harness's own drop narration by spawning `claude --debug-file <scratch> -p` and
# parsing `Ignoring dangerous permission <rule> from <path> (bypasses
# classifier)` lines. The prediction stays the default read path: the oracle
# costs a real session spawn (tokens, and the session writes its own state — see
# the cost notice) and parses undocumented [DEBUG] strings with no stability
# contract. Never spawned without the flag; never spawned silently. Criterion
# 8's defensive contract binds this read too: exit status is never trusted, a
# missing or empty capture is reported as "oracle unavailable" and the
# prediction stands — an empty capture is NEVER read as an empty drop set.
#
# Test seams:
#   ENTRY_DIFF_ORACLE_CAPTURE  parse this capture file instead of spawning
#   ENTRY_DIFF_ORACLE_PROMPT   probe prompt (default "Reply with exactly: OK")
#
# Prerequisites: POSIX text tools only. The oracle additionally needs `claude`
# on PATH; absent, it degrades to "oracle unavailable" and the prediction stands.
#
# Usage:
#   permission-state.sh | permission-merge.sh | automode-entry-diff.sh
#   automode-entry-diff.sh [--diff-only] [--oracle] [--help]

set -uo pipefail

usage() {
  cat <<'EOF'
automode-entry-diff.sh — classify what entering auto mode drops from the effective allow set.

Usage: permission-state.sh | permission-merge.sh | automode-entry-diff.sh [--diff-only] [--oracle]
       automode-entry-diff.sh [--diff-only] [--oracle] [--help]

  (no arg)      input records pass through, then the diff section
  --diff-only   the diff section alone
  --oracle      ALSO spawn a claude session (real token cost, real side effects —
                a cost notice prints before anything is spawned) and cross-check
                the prediction against the harness's own drop narration
  --help        this message

Records: "entry-diff dropped class=<class> scopes=<a,b> <rule>",
"entry-diff suspended reason=classifyAllShell scopes=<a,b> <rule>",
"entry-diff kept scopes=<a,b> <rule>", a closing "entry-diff summary" count line,
and with --oracle one "oracle AGREES <rule>" or "oracle DIVERGES ..." per compared rule.

Reads only; writes nothing except the oracle's scratch capture. Exits 2 when the
input carries no records at all.
EOF
}

diff_only=0
oracle=0
for arg in "$@"; do
  case "$arg" in
  -h | --help)
    usage
    exit 0
    ;;
  --diff-only) diff_only=1 ;;
  --oracle) oracle=1 ;;
  *)
    echo "ERROR: unknown argument '$arg'" >&2
    exit 2
    ;;
  esac
done

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
PATTERNS_LIB="$PLUGIN_ROOT/lib/permission-patterns.sh"
if [[ ! -r "$PATTERNS_LIB" ]]; then
  echo "ERROR: cannot read $PATTERNS_LIB — the shared drop vocabulary is missing, so the drop set cannot be classified" >&2
  exit 2
fi
# shellcheck source=../../../lib/permission-patterns.sh
source "$PATTERNS_LIB"

if [[ -t 0 ]]; then
  MERGE_SCRIPT="${BASH_SOURCE[0]%/*}/permission-merge.sh"
  if [[ ! -r "$MERGE_SCRIPT" ]]; then
    echo "ERROR: cannot read $MERGE_SCRIPT — nothing to diff" >&2
    exit 2
  fi
  records="$(bash "$MERGE_SCRIPT")" || exit $?
else
  records="$(cat)"
fi

if [[ -z "$records" ]]; then
  echo "ERROR: no records on input — automode-entry-diff.sh will not report a drop set it never read" >&2
  exit 2
fi

[[ "$diff_only" == 1 ]] || printf '%s\n' "$records"

# --- classifyAllShell resolution --------------------------------------------
#
# Managed is the highest settings scope, so a managed value wins over user.
# conf records from scopes the classifier does not read change nothing here and
# are called out instead of silently honored.
cas_value=""
cas_scope=""
cas_ignored=""
while read -r rec scope _surface key value _; do
  [[ "$rec" == "conf" && "$key" == "classifyAllShell" ]] || continue
  case "$scope" in
  managed)
    cas_value="$value"
    cas_scope="managed"
    ;;
  user)
    if [[ "$cas_scope" != "managed" ]]; then
      cas_value="$value"
      cas_scope="user"
    fi
    ;;
  *) cas_ignored="${cas_ignored:+$cas_ignored, }$scope" ;;
  esac
done <<<"$records"

cas_active=0
if [[ "$cas_value" == "true" ]]; then
  cas_active=1
  echo "DIFF-NOTE: autoMode.classifyAllShell is true in $cas_scope settings — every Bash and PowerShell allow rule is suspended while auto mode is active, so narrow shell rules do NOT carry over. Requires Claude Code v2.1.193 or later; earlier versions ignore the key and carry narrow rules."
elif [[ -n "$cas_value" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell in $cas_scope settings is '$cas_value', not the documented boolean true — treated as inactive here; the harness's handling of a non-boolean value is undocumented."
fi
if [[ -n "$cas_ignored" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell also appears in scope(s) the classifier does not read ($cas_ignored) — the classifier reads autoMode from user settings, managed settings, and inline --settings/SDK JSON only. Those entries have no effect and are not part of this diff."
fi

# --- Per-rule classification --------------------------------------------------

n_before=0 n_dropped=0 n_suspended=0 n_kept=0
predicted_dropped=""
diff_lines=""
while read -r rec kind scopes_field _basis rule; do
  [[ "$rec" == "effective" && "$kind" == "allow" && -n "$rule" ]] || continue
  n_before=$((n_before + 1))
  tool="${rule%%(*}"
  verdict=""
  if [[ "$rule" == "Agent" || "$rule" == "Agent("* ]]; then
    verdict="dropped class=agent"
  elif printf '%s\n' "$rule" | grep -qE "$CCPERM_P1_BLANKET_ERE"; then
    verdict="dropped class=blanket"
  elif printf '%s\n' "$rule" | grep -qE "$CCPERM_P1_INTERP_ERE|$CCPERM_P1_SCRIPTGLOB_ERE"; then
    verdict="dropped class=interpreter-wildcard"
  elif printf '%s\n' "$rule" | grep -qE "$CCPERM_P1_RUNNER_ERE"; then
    verdict="dropped class=package-manager-run"
  elif [[ "$cas_active" == 1 && ("$tool" == "Bash" || "$tool" == "PowerShell") ]]; then
    verdict="suspended reason=classifyAllShell"
  fi
  if [[ "$verdict" == dropped* ]]; then
    n_dropped=$((n_dropped + 1))
    predicted_dropped="${predicted_dropped}${rule}"$'\n'
  elif [[ "$verdict" == suspended* ]]; then
    n_suspended=$((n_suspended + 1))
    predicted_dropped="${predicted_dropped}${rule}"$'\n'
  else
    verdict="kept"
    n_kept=$((n_kept + 1))
  fi
  diff_lines="${diff_lines}entry-diff $verdict $scopes_field $rule"$'\n'
done <<<"$records"

printf '%s' "$diff_lines"
echo "entry-diff summary allow_before=$n_before dropped=$n_dropped suspended=$n_suspended kept=$n_kept"

[[ "$oracle" == 1 ]] || exit 0

# --- Debug-channel oracle (opt-in, priced) ------------------------------------

capture="${ENTRY_DIFF_ORACLE_CAPTURE:-}"
if [[ -z "$capture" ]]; then
  cat >&2 <<'EOF'
ORACLE COST NOTICE — nothing has been spawned yet.
  --oracle starts a real `claude -p` session on this machine to capture the
  harness's own drop narration. That costs API tokens, and the session leaves
  state behind like any -p session: a transcript and project entry under your
  Claude config directory (~/.claude by default) and updated internal state
  files there. It does NOT modify any settings file. The debug capture itself
  goes to a scratch path, never to ~/.claude/debug/.
EOF
  if ! command -v claude >/dev/null 2>&1; then
    echo "oracle UNAVAILABLE: 'claude' is not on PATH — the prediction above stands, uncorroborated."
    exit 0
  fi
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/entry-diff-oracle.XXXXXX")" || {
    echo "oracle UNAVAILABLE: could not create a scratch directory — the prediction above stands, uncorroborated."
    exit 0
  }
  capture="$scratch/capture.log"
  # The probe session must be IN auto mode or the channel narrates no drops:
  # measured 2026-08-11 on 2.1.225, the drop lines appear exactly when the
  # session's permission mode is auto (via --permission-mode auto here, so the
  # result does not depend on the consumer's defaultMode). Exit status is
  # deliberately not consulted — the capture file is the evidence either way.
  claude --debug-file "$capture" --permission-mode auto -p "${ENTRY_DIFF_ORACLE_PROMPT:-Reply with exactly: OK}" >/dev/null 2>&1 || true
fi

if [[ ! -s "$capture" ]]; then
  echo "oracle UNAVAILABLE: the capture at ${capture:-<none>} is missing or empty — a session that produced no usable output is reported as exactly that, never as an empty drop set. The prediction above stands, uncorroborated."
  exit 0
fi
if ! grep -q 'Applying permission update' "$capture"; then
  echo "oracle UNAVAILABLE: the capture carries no permission-merge narration (the undocumented [DEBUG] strings may have changed, or the session did not reach the merge) — the prediction above stands, uncorroborated."
  exit 0
fi

# `Ignoring dangerous permission <rule> from <abs path> (bypasses classifier)`.
# The rule text is everything up to the LAST " from ", because a rule may
# legitimately contain that word (`Bash(python3 import from x *)`) and a
# leftmost strip would truncate it there. `sed` alternation is leftmost-first
# with no greedy-suffix form, so the last occurrence is taken by anchoring a
# greedy `.*` on the prefix instead: `\(.*\) from ` consumes as much as it can
# before the final separator. The trailing path never contains " from ".
oracle_dropped="$(sed -n 's/^.*Ignoring dangerous permission \(.*\) (bypasses classifier).*$/\1/p' "$capture" |
  sed 's/^\(.*\) from [^ ].*$/\1/' | LC_ALL=C sort -u)"

if [[ -z "$oracle_dropped" ]]; then
  echo "oracle NOTE: the session narrated the permission merge but emitted zero drop lines. If this machine has rules the prediction above says are dropped, the session was likely not in auto mode; treat the oracle as unavailable rather than as an empty drop set."
  [[ -z "$(printf '%s' "$predicted_dropped")" ]] || exit 0
fi

# Compare on rule text over the union of both sets: one verdict line per rule,
# exactly — a disagreement in EITHER direction is a finding.
predicted_sorted="$(printf '%s' "$predicted_dropped" | LC_ALL=C sort -u)"
while IFS= read -r rule; do
  [[ -n "$rule" ]] || continue
  in_pred=0
  in_orc=0
  grep -qxF "$rule" <<<"$predicted_sorted" && in_pred=1
  grep -qxF "$rule" <<<"$oracle_dropped" && in_orc=1
  if [[ "$in_pred" == 1 && "$in_orc" == 1 ]]; then
    echo "oracle AGREES $rule"
  elif [[ "$in_pred" == 1 ]]; then
    echo "oracle DIVERGES prediction=dropped oracle=kept $rule"
  else
    echo "oracle DIVERGES prediction=kept oracle=dropped $rule"
  fi
done < <(printf '%s\n%s\n' "$predicted_sorted" "$oracle_dropped" | grep -v '^$' | LC_ALL=C sort -u)

exit 0
