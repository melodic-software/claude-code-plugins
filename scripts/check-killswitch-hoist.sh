#!/usr/bin/env bash
# Gate: a PreToolUse guard reads its kill switch BEFORE it sources any library.
#
#   scripts/check-killswitch-hoist.sh   fail on any PreToolUse guard whose
#                                       kill switch sits below a `source` line
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
# Scope: guards registered on PreToolUse in `plugins/*/hooks/hooks.json` and
# implemented as shell scripts. A guard implemented in another language sources
# no shell library, has no `source` line to sit above, and is reported as NOT
# SCANNED rather than passed silently — today that is disk-hygiene's
# destructive_guard.py and context-budget's node handler.
#
# Exit 0 = clean; 1 = one or more violations; 1 also for an environment problem
# (fail closed — never a silent skip).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-killswitch-hoist: jq is required but not installed" >&2
  exit 1
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

# --- discover the PreToolUse guards -----------------------------------------
# Every token ending in `.sh` inside a PreToolUse command names a guard, except
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
    # A PreToolUse row that named no shell guard is a guard this gate's rule does
    # not reach — a Python or node handler behind a launcher, or a bare
    # interpreter. Reported, never silently passed.
    ((saw_guard)) || unscanned+=("$hooks_json")
  done < <(jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$hooks_json")
done

if ((${#guards[@]} == 0)); then
  echo "check-killswitch-hoist: no PreToolUse shell guards found — refusing to report clean" >&2
  exit 1
fi

# De-duplicate: one guard may be registered on several matchers.
mapfile -t guards < <(printf '%s\n' "${guards[@]}" | sort -u)

# --- the rule ----------------------------------------------------------------
# Three accepted inlined shapes. The first two are the ordinary default-on and
# opt-in guards; the third is a strict-and-loud guard hoisting only its DISABLED
# arm, because its "neither true nor false" arm must speak through a library
# function and cannot run before the library exists.
SWITCH_RE='^\[\[ "\$\{CLAUDE_PLUGIN_OPTION_[A-Z0-9_]+_ENABLED:-(true|false)\}" == "(true|false)" \]\] (\|\| exit 0|&& exit 0)$'
SOURCE_RE='^[[:space:]]*(source|\.)[[:space:]]+'

violations=0
for guard in "${guards[@]}"; do
  if [[ ! -f "$guard" ]]; then
    echo "VIOLATION: $guard — registered on PreToolUse but missing from the tree" >&2
    violations=$((violations + 1))
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
    {
      echo "VIOLATION: $guard:$legacy_line — calls hook::check_enabled."
      echo "  That helper only exists after the library is sourced, which is the cost"
      echo "  the hoist exists to avoid. Inline the predicate above the source instead:"
      # shellcheck disable=SC2016  # a template for the reader to paste, meant literally
      echo '    [[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0'
    } >&2
    violations=$((violations + 1))
    continue
  fi

  if ((switch_line == 0)); then
    {
      echo "VIOLATION: $guard — no inlined kill switch found."
      echo "  Expected, above the first source line:"
      # shellcheck disable=SC2016  # a template for the reader to paste, meant literally
      echo '    [[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0'
    } >&2
    violations=$((violations + 1))
    continue
  fi

  if ((source_line > 0 && switch_line > source_line)); then
    {
      echo "VIOLATION: $guard — kill switch at line $switch_line is BELOW the source at line $source_line."
      echo "  A disabled guard must not pay to parse a library before finding out it is off."
    } >&2
    violations=$((violations + 1))
    continue
  fi
done

if ((${#unscanned[@]} > 0)); then
  mapfile -t unscanned < <(printf '%s\n' "${unscanned[@]}" | sort -u)
  printf 'check-killswitch-hoist: NOT SCANNED (PreToolUse guard is not a shell script): %s\n' "${unscanned[@]}"
fi

if ((violations > 0)); then
  echo "check-killswitch-hoist: $violations violation(s)" >&2
  exit 1
fi

printf 'check-killswitch-hoist: %d PreToolUse guard(s) read their kill switch before any source\n' "${#guards[@]}"
