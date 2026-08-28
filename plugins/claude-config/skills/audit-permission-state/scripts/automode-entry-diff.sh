#!/usr/bin/env bash
# automode-entry-diff.sh — what entering auto mode does to the effective allow
# set, per rule, with the drop reason named.
#
# "On entering auto mode, broad allow rules that grant arbitrary code execution
# are dropped: Blanket Bash(*) or PowerShell(*); Wildcarded interpreters like
# Bash(python*); Package-manager run commands; Agent allow rules; Monitor allow
# rules, because Claude Code runs Monitor commands through the shell. Narrow
# rules like Bash(npm test) carry over." This script classifies every effective
# allow rule from the merge into exactly one of those documented classes or
# `kept`, using the same shared vocabulary (lib/permission-patterns.sh) that
# audit-permission-grants check P1 scans with — one definition, two consumers.
# The two whole-tool classes (Agent, Monitor) carry no shell shape, so they are
# tested on the tool token here rather than through that vocabulary.
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
#   class  blanket | interpreter-wildcard | package-manager-run | agent | monitor
#          (the documented five; the vocabulary's script-glob alternative is an
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

Writes no settings file. Without --oracle it writes nothing at all; with it, the
capture goes to a scratch path AND the spawned session leaves its own state
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
elif [[ "$cas_value" == "false" ]]; then
  # `false` is the documented default and a perfectly valid setting. Describing
  # it as a type error told an operator their correct configuration was wrong.
  echo "DIFF-NOTE: autoMode.classifyAllShell is false in $cas_scope settings (the default), so narrow Bash and PowerShell allow rules carry over into auto mode as usual."
elif [[ -n "$cas_value" ]]; then
  echo "DIFF-NOTE: autoMode.classifyAllShell in $cas_scope settings is $cas_value, which is neither of the documented boolean values — treated as inactive here; the harness's handling of a non-boolean value is undocumented."
fi
# The classifier reads autoMode from THREE sources and this reader can see two.
# Inline --settings / SDK JSON has no file to open, and it can invert the whole
# answer: classifyAllShell true there suspends every shell allow rule while this
# diff reports them kept. The merge's command-line caveat covers RULES, not this
# key, so it is stated here or nowhere.
echo "DIFF-NOTE: inline --settings and Agent SDK JSON are a third scope the classifier reads autoMode from, and they have no file for this reader to open. If classifyAllShell is set there, every Bash and PowerShell verdict below is inverted — this diff reflects the settings FILES only."
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
  elif [[ "$rule" == "Monitor" || "$rule" == "Monitor("* ]]; then
    # Upstream added Monitor to the dropped list in v2.1.236, "because Claude
    # Code runs Monitor commands through the shell". It behaves like Agent, not
    # like Bash: the whole class drops, so a scoped Monitor(...) rule is NOT a
    # narrow carry-over. Reporting one as kept would tell an operator a grant
    # survives that the harness has already suspended.
    verdict="dropped class=monitor"
  elif [[ "$rule" == "Bash" || "$rule" == "PowerShell" ]]; then
    # A bare tool name is the WHOLE-TOOL grant -- strictly broader than
    # Bash(*), which this same run classifies as blanket. Reporting it as
    # surviving auto mode while dropping the narrower form would be backwards
    # in the direction that matters: it tells an operator their broadest shell
    # grant is safe. The Agent branch above already handles its own bare form;
    # this is the same rule for the two shell tools.
    verdict="dropped class=blanket"
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
  harness's own drop narration. That costs API tokens, and the session writes
  outside the scratch capture path. Measured on 2.1.225 / Windows 11 by
  checksumming before and after a probe run:
    - Your settings files are NOT modified: ~/.claude/settings.json and
      ~/.claude/settings.local.json were byte-identical afterwards.
    - ~/.claude.json IS rewritten. It is the harness's own state file, not a
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
  capture="$scratch/capture.log"
  # `--permission-mode auto` is passed so the probe does not depend on the
  # consumer's own defaultMode. What was actually MEASURED is narrower than that
  # framing suggests, and reference/criteria.md carries the measurement: a `-p`
  # run with NO mode flag emitted 216 drop lines, on a machine whose defaultMode
  # may already have been auto. So the flag is known-valid (`claude --help`
  # lists `auto`) and known-harmless, but "drops appear only in auto mode" is
  # NOT established — it is a plausible reading of one capture. The zero-drop
  # path below degrades to `unavailable` precisely because this is unproven.
  #
  # Exit status is deliberately not consulted — the capture file is the evidence
  # either way.
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
# This strips the fixed prefix and suffix; splitting rule from path is the
# block below, which explains how.
oracle_raw="$(sed -n 's/^.*Ignoring dangerous permission \(.*\) (bypasses classifier).*$/\1/p' "$capture")"

# Neither field is delimited, so a line carrying more than one " from " must be
# RESOLVED rather than guessed at. The discriminator is the RULE side, not the
# path: a permission rule is a tool token, optionally with one parenthesized
# payload, and that grammar already exists as CCPERM_TOOL_TOKEN_ERE in the shared
# vocabulary. Each candidate separator is tried and kept only when the text to
# its left is a well-formed rule.
#
# That distinguishes the two cases a single expression cannot. In
# `Bash(python3 import from x *) from <path>` the first candidate leaves
# `Bash(python3 import` -- unbalanced, rejected. In
# `Bash(uv run *) from C:\...\notes from work\...\settings.json` the second
# leaves `Bash(uv run *) from C:\...\notes` -- not a tool token, rejected. Each
# resolves to exactly one survivor, and the path may contain anything at all.
# The grammar is checked structurally rather than by regex: awk strips the
# backslashes out of an ERE passed through -v, which turns the vocabulary's
# escaped parens into grouping and matches nothing. Balance and shape are what
# matter here, and both are cheaper to check directly than to re-escape.
split_lines="$(printf '%s\n' "$oracle_raw" | awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # A rule is a tool token, optionally followed by ONE balanced parenthesized
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

# Everything else carries a real harness drop this run cannot name. Saying so
# beats guessing, and beats dropping them in silence.
oracle_unparsed="$(printf '%s\n' "$split_lines" | sed -n 's/^AMBIGUOUS\t//p')"
if [[ -n "$oracle_unparsed" ]]; then
  n_unparsed="$(printf '%s\n' "$oracle_unparsed" | grep -c .)"
  echo "oracle NOTE: $n_unparsed drop line(s) could not be split into rule and source path — the narration delimits neither field, and no candidate split left a well-formed rule on the left (or more than one did). Those drops are real and are NOT reflected in the verdicts below; treat this comparison as incomplete rather than clean."
fi

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
