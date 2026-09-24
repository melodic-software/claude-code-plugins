#!/usr/bin/env bash
# Gate: a hook finds out it has nothing to do BEFORE it sources any library.
#
#   scripts/check-killswitch-hoist.sh   rule 1: fail on any PreToolUse or
#                                       PostToolUse hook script whose kill
#                                       switch sits below a `source` line
#                                       rule 2: fail on any blocking hook
#                                       script, on any event, whose first early
#                                       exit sits below a `source` line
#
# Rule 2 exists because the per-turn hooks (Stop, Notification, SessionEnd and
# the rest) paid the same cost rule 1 removed from the tool hooks: a disabled
# or unarmed hook parsed hook-utils.sh before its first `exit 0` (#4415, fixed
# for lane-stop-gate.sh in #4421). Most of those hooks have no `_enabled`
# switch, so rule 1 cannot hold them; rule 2 asks only that whatever early exit
# a hook has comes first. Async hooks are exempt (they do not block); see the
# discovery block below for the documented exceptions.
#
# Why: every guard ships a `<name>_enabled` userConfig boolean, and an operator
# who turns one off is entitled to stop paying for it. Until #3719 all of them
# read that switch through `hook::check_enabled`, a function that only exists
# once `lib/hook-utils.sh` has been sourced — so a DISABLED guard parsed the
# whole 2,684-line library before discovering it had nothing to do. Measured on
# this repo's Linux CI host: a bare `bash -c 'exit 0'` costs 1.8 ms and the same
# process with hook-utils sourced costs 5.3 ms, so the library is ~3.5 ms of a
# disabled standalone guard's ~5.3 ms.
#
# The saving is UNEVEN, and the honest split matters more than the headline.
# Four of the fifteen PreToolUse guards run as their own process
# (source-control's three, context-guard's zone-gate) and recover the full
# ~3.5 ms. The other eleven are sourced into one process by
# `plugins/guardrails/hooks/run-guards.sh`, which has already loaded the library
# for its own use; hook-utils.sh carries an include guard (`_HOOK_UTILS_LOADED`),
# so their `source` line costs ~0.05 ms and the hoist buys them almost nothing.
# They are held to the same rule anyway: one shape across the fleet is what
# makes this mechanically checkable, and each of them is also invoked
# standalone — by its own contract test today, and by a hooks.json that
# registered it directly tomorrow.
#
# Why a gate rather than a convention: `scripts/sync-hook-utils.sh` synchronizes
# the vendored library copies but does NOT cover the entry scripts, so nothing
# else in this repo would notice the ordering drifting back. The audit that
# prompted this found the switch below the source in 43 of 43 hooks — the shape
# reasserts itself unless something fails.
#
# The rule, per PreToolUse guard script:
#   1. it carries a recognized inlined kill-switch line;
#   2. that line comes before the first `source` / `.` of any file;
#   3. it does not ALSO call `hook::check_enabled` (the un-hoisted form).
#
# Semantics are pinned, not just position: the inlined predicate must agree with
# `hook::is_enabled` in lib/hook-utils.sh, which is the definition it duplicates.
# If that helper's own reading of the env var changes, this gate fails and the
# fifteen copies get revisited rather than silently diverging. That pin is the
# price of inlining, and it is why inlining is acceptable here at all.
#
# Scope of rule 1: hooks registered on PreToolUse or PostToolUse in
# `plugins/*/hooks/hooks.json` and implemented as shell scripts. Rule 2 covers
# every event in the same files, with the same token walk. PostToolUse
# joined the scope with the formatter, normalizer and verifier hoist (the
# per-tool-call rows the hook budget counts): the same shape, the same pin, one
# gate. A hook implemented in another language sources no shell library, has no
# `source` line to sit above, and is reported as NOT SCANNED rather than passed
# silently — today that is disk-hygiene's destructive_guard.py and
# context-budget's node handler.
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr. That is
# the whole family's contract, stated once in README.md, "The check-script
# contract", and held by scripts/check-script-contract.test.sh. Two fail-closed
# stops stay at 1 because they are statements about the TREE rather than about
# this host: a hook corpus that scans to empty, and an inlined predicate that no
# longer agrees with the hook::is_enabled it duplicates.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

if ! command -v jq >/dev/null 2>&1; then
  echo "check-killswitch-hoist: jq is required but not installed" >&2
  exit 2
fi

HOOK_UTILS="lib/hook-utils.sh"

# --- the semantic pin --------------------------------------------------------
# hook::is_enabled is two lines; both are asserted, because both are what the
# inlined copies reproduce: the env-var NAME it builds, and the unset-default it
# compares. A guard whose plugin.json default is false inlines `:-false`
# instead, which is a deliberate divergence the rule below admits by shape.
pin_ok=0
if [[ -f "$HOOK_UTILS" ]]; then
  is_enabled_body="$(awk '/^hook::is_enabled\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$HOOK_UTILS")"
  # shellcheck disable=SC2016  # the helper's own source text, matched verbatim; nothing here should expand
  if [[ "$is_enabled_body" == *'CLAUDE_PLUGIN_OPTION_${1}_ENABLED'* &&
    "$is_enabled_body" == *'${!var_name:-true}'* &&
    "$is_enabled_body" == *'== "true"'* ]]; then
    pin_ok=1
  fi
fi
if ((pin_ok == 0)); then
  {
    echo "check-killswitch-hoist: hook::is_enabled in $HOOK_UTILS no longer reads"
    echo "  CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED with an unset default of \"true\"."
    echo "  The PreToolUse guards inline that predicate above their library source,"
    echo "  so a change here means those copies must be revisited together."
    echo "  Update this pin and the guards in the same change."
  } >&2
  exit 1
fi

# --- discover the PreToolUse and PostToolUse hooks ---------------------------
# Every token ending in `.sh` inside a PreToolUse or PostToolUse command names a
# guard (the word is kept for every scanned script; a formatter is held to the
# same rule as a guard and the rule does not care what the script does), except
# a LAUNCHER (below) and a `--lib` value (a bundled classifier, not a guard).
# Bare names are launcher arguments and resolve under the same plugin's hooks/
# directory.
#
# A launcher takes the real guard as an argument and owns no `<name>_enabled`
# switch of its own, so it has nothing to hoist. The distinction is by name
# rather than by inspection because "does this script dispatch to another" is not
# decidable from the file, and a wrong guess in either direction is worse than a
# short list: admitting a launcher fails the gate forever, and excluding a real
# guard clears one that was never checked.
#   run-guards.sh      — guardrails' PreToolUse/PostToolUse dispatcher; sources
#                        each named guard, and each of those carries its own switch
#   run-python-hook.sh — disk-hygiene's interpreter resolver (#1504); execs the
#                        Python guard, whose switch is disk_hygiene_enabled and
#                        lives in destructive_guard.py
LAUNCHERS=("run-guards.sh" "run-python-hook.sh")

is_launcher() {
  local candidate="$1" known
  for known in "${LAUNCHERS[@]}"; do
    [[ "$candidate" == "$known" ]] && return 0
  done
  return 1
}

guards=()
unscanned=()
for hooks_json in plugins/*/hooks/hooks.json; do
  [[ -f "$hooks_json" ]] || continue
  hooks_dir="$(dirname "$hooks_json")"
  while IFS= read -r command; do
    [[ -n "$command" ]] || continue
    saw_guard=0
    skip_next=0
    # Split into words but never glob: a `*` token is text, not a path under
    # the repository root.
    set -f
    # shellcheck disable=SC2086  # deliberate word split: the command is a shell command line
    for token in $command; do
      token="${token%\"}"
      token="${token#\"}"
      if ((skip_next)); then
        skip_next=0
        continue
      fi
      if [[ "$token" == "--lib" ]]; then
        skip_next=1
        continue
      fi
      [[ "$token" == *.sh ]] || continue
      base="${token##*/}"
      # shellcheck disable=SC2310  # is_launcher is a pure lookup with no set -e-sensitive body; a false return is the intended "not a launcher"
      is_launcher "$base" && continue
      saw_guard=1
      guards+=("$hooks_dir/$base")
    done
    set +f
    # A scanned row that named no shell script is a hook this gate's rule does
    # not reach — a Python or node handler behind a launcher, or a bare
    # interpreter. Reported, never silently passed.
    ((saw_guard)) || unscanned+=("$hooks_json")
  done < <(jq -r '(.hooks.PreToolUse[]?, .hooks.PostToolUse[]?) | .hooks[]?.command // empty' "$hooks_json")
done

# --- discover every blocking hook, on any event (rule 2) ----------------------
# Same token walk, over every event. A row with `async: true` is skipped: the
# hooks reference (https://code.claude.com/docs/en/hooks, "Run hooks in the
# background", fetched 2026-09-24) says "Set `async: true` on a command hook to
# spawn it in the background without blocking ... Claude Code doesn't await the
# result". The same section says async is ignored on four events: "`UserPromptSubmit`,
# `UserPromptExpansion`, `PreModelSwitch`, and `MessageDisplay` require
# synchronous hooks. When you set `async: true` on a hook for one of those
# events, Claude Code ignores it and runs the hook synchronously instead." So an
# async row on those four is still scanned. SessionStart is scanned: that page
# says only that "Exit code 2 isn't honored for this event", and nowhere that a
# SessionStart hook runs in the background or does not delay the session.
SYNC_ONLY_EVENTS=" UserPromptSubmit UserPromptExpansion PreModelSwitch MessageDisplay "
blocking=()
unreadable=()
for hooks_json in plugins/*/hooks/hooks.json; do
  [[ -f "$hooks_json" ]] || continue
  hooks_dir="$(dirname "$hooks_json")"
  # Captured, not streamed: a jq that stops part-way (a non-object hook entry,
  # invalid JSON) must fail the gate rather than hand back a truncated row list.
  if ! rows="$(jq -r '.hooks | to_entries[] | .key as $e | .value[]? | .hooks[]?
    | select(.command | type == "string")
    | [$e, (.async == true | tostring), .command] | @tsv' "$hooks_json" 2>/dev/null)"; then
    unreadable+=("$hooks_json")
    continue
  fi
  while IFS=$'\t' read -r event async command; do
    command="${command%$'\r'}"
    [[ -n "$command" ]] || continue
    [[ "$async" == true && "$SYNC_ONLY_EVENTS" != *" $event "* ]] && continue
    saw_guard=0
    skip_next=0
    set -f # word split without globbing, as in the PreToolUse walk above
    # shellcheck disable=SC2086  # deliberate word split: the command is a shell command line
    for token in $command; do
      token="${token%\"}"
      token="${token#\"}"
      if ((skip_next)); then
        skip_next=0
        continue
      fi
      if [[ "$token" == "--lib" ]]; then
        skip_next=1
        continue
      fi
      [[ "$token" == *.sh ]] || continue
      base="${token##*/}"
      # shellcheck disable=SC2310  # see the PreToolUse walk above
      is_launcher "$base" && continue
      saw_guard=1
      blocking+=("$hooks_dir/$base")
    done
    set +f
    ((saw_guard)) || unscanned+=("$hooks_json")
  done <<<"$rows"
done

if ((${#guards[@]} == 0 && ${#blocking[@]} == 0)); then
  echo "check-killswitch-hoist: no shell hook scripts found on any event — refusing to report clean" >&2
  exit 1
fi

# De-duplicate: one guard may be registered on several matchers.
if ((${#guards[@]} > 0)); then
  mapfile -t guards < <(printf '%s\n' "${guards[@]}" | sort -u)
fi
if ((${#blocking[@]} > 0)); then
  mapfile -t blocking < <(printf '%s\n' "${blocking[@]}" | LC_ALL=C sort -u)
fi

# --- the rule ----------------------------------------------------------------
# Three accepted inlined shapes. The first two are the ordinary default-on and
# opt-in guards; the third is a strict-and-loud guard hoisting only its DISABLED
# arm, because its "neither true nor false" arm must speak through a library
# function and cannot run before the library exists.
SWITCH_RE='^\[\[ "\$\{CLAUDE_PLUGIN_OPTION_[A-Z0-9_]+_ENABLED:-(true|false)\}" == "(true|false)" \]\] (\|\| exit 0|&& exit 0)$'
SOURCE_RE='^[[:space:]]*(source|\.)[[:space:]]+'

# The remedy template every "fix it this way" finding prints, so the two that
# quote it cannot drift apart.
# shellcheck disable=SC2016  # a template for the reader to paste, meant literally
HOIST_TEMPLATE='    [[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0'

violations=0

# violation <line>...: one finding on stderr, counted.
violation() {
  printf '%s\n' "$@" >&2
  violations=$((violations + 1))
}

for guard in "${guards[@]}"; do
  if [[ ! -f "$guard" ]]; then
    violation "VIOLATION: $guard — registered on PreToolUse or PostToolUse but missing from the tree"
    continue
  fi

  switch_line=0
  source_line=0
  legacy_line=0
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    if ((switch_line == 0)) && [[ "$line" =~ $SWITCH_RE ]]; then
      switch_line=$n
    fi
    if ((source_line == 0)) && [[ "$line" =~ $SOURCE_RE ]]; then
      source_line=$n
    fi
    if ((legacy_line == 0)) && [[ "$line" =~ ^hook::check_enabled[[:space:]] ]]; then
      legacy_line=$n
    fi
  done <"$guard"

  # The legacy call is reported FIRST when both apply. A guard mid-migration has
  # the call and not yet the inlined line, and "you are still using the helper"
  # names the fix; "no kill switch found" would read as though the guard had none
  # at all and send the reader looking for the wrong thing.
  if ((legacy_line > 0)); then
    violation "VIOLATION: $guard:$legacy_line — calls hook::check_enabled." \
      "  That helper only exists after the library is sourced, which is the cost" \
      "  the hoist exists to avoid. Inline the predicate above the source instead:" \
      "$HOIST_TEMPLATE"
    continue
  fi

  if ((switch_line == 0)); then
    violation "VIOLATION: $guard — no inlined kill switch found." \
      "  Expected, above the first source line:" \
      "$HOIST_TEMPLATE"
    continue
  fi

  if ((source_line > 0 && switch_line > source_line)); then
    violation "VIOLATION: $guard — kill switch at line $switch_line is BELOW the source at line $source_line." \
      "  A disabled guard must not pay to parse a library before finding out it is off."
  fi
done

# --- rule 2: the first early exit comes before the first source -------------
# An early exit is an `exit 0` or a hook::check_enabled call (which exits 0 when
# the switch is off) on a code line other than the script's last. A script with
# no early exit has nothing to hoist and passes; a script whose first early exit
# sits below a `source` pays for the library on the path that does nothing.
# ponytail: textual; an `exit 0` inside a function defined above the source
# counts as early. Upgrade to a real parse if that shape ever ships.
#
# `# hoist-ok: <reason>` on the first early exit's line, or on the line directly
# above it, excuses the order. It applies only when that exit's test needs
# something the library provides and has no cheaper form to hoist; the reason
# says which. It is ignored on a hook::check_enabled call: a kill switch is
# always inlinable.
EARLY_EXIT_RE='(^|[[:space:];&|(])exit 0([[:space:];)]|$)|^[[:space:]]*hook::check_enabled[[:space:]]'
for hooks_json in ${unreadable[@]+"${unreadable[@]}"}; do
  violation "VIOLATION: $hooks_json — not readable as a hooks config; this gate cannot clear it"
done
for script in ${blocking[@]+"${blocking[@]}"}; do
  if [[ ! -f "$script" ]]; then
    violation "VIOLATION: $script — registered as a hook but missing from the tree"
    continue
  fi
  source_line=0
  exit_line=0
  last_code=0
  exit_text=""
  exit_marked=0
  prev=""
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    above="$prev"
    prev="$line"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    last_code=$n
    if ((source_line == 0)) && [[ "$line" =~ $SOURCE_RE ]]; then
      source_line=$n
    fi
    if ((exit_line == 0)) && [[ "${line%%[[:space:]]#*}" =~ $EARLY_EXIT_RE ]]; then
      exit_line=$n
      exit_text="$line"
      if [[ "$line" == *hoist-ok:* || "$above" == *hoist-ok:* ]] &&
        [[ ! "$line" =~ hook::check_enabled ]]; then
        exit_marked=1
      fi
    fi
  done <"$script"
  ((exit_line == last_code)) && exit_line=0
  ((source_line > 0 && exit_line > source_line && exit_marked == 0)) || continue
  if [[ "$exit_text" =~ hook::check_enabled ]]; then
    violation "VIOLATION: $script:$exit_line — calls hook::check_enabled below the source at line $source_line." \
      "  That helper only exists after the library is sourced, which is the cost" \
      "  the hoist exists to avoid. Inline the predicate above the source instead:" \
      "$HOIST_TEMPLATE"
  else
    violation "VIOLATION: $script — first early exit at line $exit_line is BELOW the source at line $source_line." \
      "  A hook that has nothing to do must find out before it parses a library;" \
      "  move the cheapest exit test above the first source."
  fi
done

if ((${#unscanned[@]} > 0)); then
  mapfile -t unscanned < <(printf '%s\n' "${unscanned[@]}" | sort -u)
  printf 'check-killswitch-hoist: NOT SCANNED (hook is not a shell script): %s\n' "${unscanned[@]}"
fi

if ((violations > 0)); then
  echo "check-killswitch-hoist: $violations violation(s)" >&2
  exit 1
fi

printf 'check-killswitch-hoist: %d PreToolUse and PostToolUse hook script(s) read their kill switch before any source; %d blocking hook script(s) on any event reach their first early exit before any source\n' \
  "${#guards[@]}" "${#blocking[@]}"
