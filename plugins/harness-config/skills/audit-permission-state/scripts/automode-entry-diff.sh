#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
automode-entry-diff.sh — classify what entering auto mode drops from the effective allow set.

Usage: permission-state.sh | permission-merge.sh | automode-entry-diff.sh [--diff-only] [--oracle]
       automode-entry-diff.sh [--diff-only] [--oracle] [--help]

  (no arg)      input records pass through, then the diff section
  --diff-only   the diff section alone
  --oracle      also spawn a claude session (real token cost, real side effects —
                a cost notice prints before anything is spawned) and cross-check
                the prediction against the harness's own drop narration
  --help        this message

Records: "entry-diff dropped class=<class> scopes=<a,b> <rule>",
"entry-diff suspended reason=classifyAllShell scopes=<a,b> <rule>",
"entry-diff kept scopes=<a,b> <rule>", a closing "entry-diff summary" count line,
and with --oracle one "oracle AGREES <rule>" or "oracle DIVERGES ..." per compared rule.

Writes no settings file. Without --oracle it writes nothing at all; with it, the
capture goes to a scratch path and the spawned session leaves its own state
under your config directory — the cost notice enumerates that. Exits 2 when the
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

if [[ "$diff_only" == 1 ]]; then
  printf '%s\n' "$records" | grep -E '^(CAVEAT|NOTE|MANAGED-NOTE|LINT-NOTE):' || true
else
  printf '%s\n' "$records"
fi

unread_scopes=""
while IFS= read -r rec; do
  # Word splitting is the point here: a surface record is positional, and $1/$3
  # are its scope and status fields.
  # shellcheck disable=SC2086 # deliberate field split on a positional record
  set -- $rec
  [[ $# -ge 3 ]] || continue
  case "$1" in
  rule | effective | inert | carveout | conf | entry-diff | CAVEAT: | NOTE: | MANAGED-NOTE: | LINT-NOTE: | DIFF-NOTE:) continue ;;
  *) ;;
  esac
  case "$3" in
  skipped | unreadable | invalid-json)
    case ",$unread_scopes," in
    *",$1,"*) ;;
    *) unread_scopes="${unread_scopes:+$unread_scopes,}$1" ;;
    esac
    ;;
  *) ;;
  esac
done <<<"$records"

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
  echo "DIFF-NOTE: autoMode.classifyAllShell is true in $cas_scope settings — every Bash and PowerShell allow rule is suspended while auto mode is active, so narrow shell rules do not carry over. Requires Claude Code v2.1.193 or later; earlier versions ignore the key and carry narrow rules."
elif [[ "$cas_value" == "false" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell is false in $cas_scope settings (the default), so narrow Bash and PowerShell allow rules carry over into auto mode as usual."
elif [[ -n "$cas_value" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell in $cas_scope settings is $cas_value, which is neither of the documented boolean values — treated as inactive here; the harness's handling of a non-boolean value is undocumented."
fi
echo "DIFF-NOTE: inline --settings and Agent SDK JSON are a third scope the classifier reads autoMode from, and they have no file for this reader to open. If classifyAllShell is set there, every Bash and PowerShell verdict below is inverted — this diff reflects the settings files only."
if [[ -n "$cas_ignored" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell also appears in scope(s) the classifier does not read ($cas_ignored) — the classifier reads autoMode from user settings, managed settings, and inline --settings/SDK JSON only. Those entries have no effect and are not part of this diff."
fi


rule_matches() { grep -qE "$2" <<<"$1"; }

n_before=0 n_dropped=0 n_suspended=0 n_kept=0
monitor_seen=0
predicted_dropped=""
diff_lines=""
while read -r rec kind scopes_field _basis rule; do
  [[ "$rec" == "effective" && "$kind" == "allow" && -n "$rule" ]] || continue
  n_before=$((n_before + 1))
  tool="${rule%%(*}"
  verdict=""
  if [[ "$rule" == "Agent" || "$rule" == "Agent("* ]]; then
    verdict="dropped class=agent"
  elif [[ "$rule" == "Monitor" || "$rule" == "Monitor("* ]]; then
    monitor_seen=1
    verdict="dropped class=monitor"
  elif [[ "$rule" == "Bash" || "$rule" == "PowerShell" ]] || rule_matches "$rule" "$CCPERM_P1_BLANKET_ERE"; then
    verdict="dropped class=blanket"
  elif rule_matches "$rule" "$CCPERM_P1_INTERP_ERE|$CCPERM_P1_SCRIPTGLOB_ERE"; then
    verdict="dropped class=interpreter-wildcard"
  elif rule_matches "$rule" "$CCPERM_P1_RUNNER_ERE"; then
    verdict="dropped class=package-manager-run"
  elif rule_matches "$rule" "$CCPERM_P1_WRAPPER_ERE"; then
    verdict="dropped class=wrapper-wildcard"
  elif rule_matches "$rule" "$CCPERM_P1_LEADING_ERE"; then
    verdict="dropped class=leading-wildcard"
  elif rule_matches "$rule" "$CCPERM_P1_PATH_ERE"; then
    verdict="dropped class=path-wildcard"
  elif [[ "$cas_active" == 1 && ("$tool" == "Bash" || "$tool" == "PowerShell") ]]; then
    verdict="suspended reason=classifyAllShell"
  fi
  if [[ -z "$verdict" ]]; then
    verdict="kept"
    n_kept=$((n_kept + 1))
  else
    predicted_dropped="${predicted_dropped}${rule}"$'\n'
    if [[ "$verdict" == dropped* ]]; then
      n_dropped=$((n_dropped + 1))
    else
      n_suspended=$((n_suspended + 1))
    fi
  fi
  diff_lines="${diff_lines}entry-diff $verdict $scopes_field $rule"$'\n'
done <<<"$records"

if [[ "$monitor_seen" == 1 ]]; then
  echo "DIFF-NOTE: a Monitor allow rule is reported as dropped. Requires Claude Code v2.1.236 or later; earlier versions leave Monitor allow rules in effect in auto mode, so on an older version that rule carries over and this verdict is inverted. This script cannot read the running version; confirm it before acting on a monitor verdict."
fi

echo "DIFF-NOTE: dropped and suspended rules alike are RESTORED when the session leaves auto mode. Neither verdict changes any settings file; both describe what is in force while auto mode is active."

echo "DIFF-NOTE: this diff applies only to a session that ENTERS auto mode. Not every session does: a 'claude -p' or Agent SDK run with no permission mode set starts in Manual and never makes this transition. Which sessions start in auto mode depends on the Claude Code version, how it is run, the provider and model, and settings such as disableAutoMode; read the current conditions at https://code.claude.com/docs/en/permission-modes#which-mode-a-session-starts-in before acting on this diff."

printf '%s' "$diff_lines"
if [[ -n "$unread_scopes" ]]; then
  echo "DIFF-NOTE: $unread_scopes scope(s) could not be read, so any allow rules they hold were never classified. The counts below cover the scopes that were read."
fi
echo "entry-diff summary allow_before=$n_before dropped=$n_dropped suspended=$n_suspended kept=$n_kept status=$([[ -n "$unread_scopes" ]] && echo incomplete || echo read)"

[[ "$oracle" == 1 ]] || exit 0


capture="${ENTRY_DIFF_ORACLE_CAPTURE:-}"
if [[ -z "$capture" ]]; then
  cat >&2 <<'EOF'
ORACLE COST NOTICE — nothing has been spawned yet.
  --oracle starts a real `claude -p` session on this machine to capture the
  harness's own drop narration. That costs API tokens, and the session writes
  outside the scratch capture path. Measured on 2.1.225 / Windows 11 by
  checksumming before and after a probe run:
    - Your settings files are not modified: ~/.claude/settings.json and
      ~/.claude/settings.local.json were byte-identical afterwards.
    - ~/.claude.json is rewritten. It is the harness's own state file, not a
      settings file, and it carries no permission rules -- but it does change.
    - New files appear under your config directory: a project entry for the
      session's working directory, a session-env entry, per-session security
      and subagent state, and a backup entry.
  The debug capture itself goes to a scratch path, never to ~/.claude/debug/.
  Run it from a directory you do not mind appearing in your project list.
EOF
  if ! command -v claude >/dev/null 2>&1; then
    echo "oracle UNAVAILABLE: 'claude' is not on PATH — the prediction above stands, uncorroborated."
    exit 0
  fi
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/entry-diff-oracle.XXXXXX")" || {
    echo "oracle UNAVAILABLE: could not create a scratch directory — the prediction above stands, uncorroborated."
    exit 0
  }
  trap 'rm -rf "$scratch"' EXIT
  capture="$scratch/capture.log"
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

oracle_raw="$(sed -n 's/^.*Ignoring dangerous permission \(.*\) (bypasses classifier).*$/\1/p' "$capture")"

split_lines="$(printf '%s\n' "$oracle_raw" | awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # A rule is a tool token, optionally followed by one balanced parenthesized
  # payload that runs to the end of the text.
  function is_rule(s,   open, i, c, depth) {
    if (s !~ /^[A-Za-z_][A-Za-z0-9_]*(\(|$)/) return 0
    open = index(s, "(")
    if (open == 0) return s ~ /^[A-Za-z_][A-Za-z0-9_]*$/
    depth = 0
    for (i = open; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "(") depth++
      else if (c == ")") { depth--; if (depth == 0) return i == length(s) }
    }
    return 0
  }
  {
    line = $0
    if (line !~ /[^ \t]/) next
    n_ok = 0; rule = ""
    start = 1
    while ((p = index(substr(line, start), " from ")) > 0) {
      at = start + p - 1
      cand = trim(substr(line, 1, at - 1))
      tail = substr(line, at + 6)
      if (is_rule(cand) && tail ~ /[^ \t]/) { n_ok++; rule = cand }
      start = at + 1
    }
    if (n_ok == 1) print "OK\t" rule
    else print "AMBIGUOUS\t" line
  }')"

oracle_dropped="$(printf '%s\n' "$split_lines" | sed -n 's/^OK\t//p' | LC_ALL=C sort -u)"

oracle_unparsed="$(printf '%s\n' "$split_lines" | sed -n 's/^AMBIGUOUS\t//p')"
if [[ -n "$oracle_unparsed" ]]; then
  n_unparsed="$(printf '%s\n' "$oracle_unparsed" | grep -c .)"
  echo "oracle NOTE: $n_unparsed drop line(s) could not be split into rule and source path — the narration delimits neither field, and no candidate split left a well-formed rule on the left (or more than one did). Those drops are real and are not reflected in the verdicts below; treat this comparison as incomplete rather than clean."
fi

if [[ -z "$oracle_dropped" ]]; then
  echo "oracle NOTE: the session narrated the permission merge but emitted zero drop lines. If this machine has rules the prediction above says are dropped, the session was likely not in auto mode; treat the oracle as unavailable rather than as an empty drop set."
  [[ -z "$predicted_dropped" ]] || exit 0
fi

predicted_sorted="$(printf '%s' "$predicted_dropped" | LC_ALL=C sort -u)"
while IFS= read -r rule; do
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
