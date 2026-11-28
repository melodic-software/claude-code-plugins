#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/hook-configs.sh
. scripts/lib/hook-configs.sh || exit 2

hook_configs::sources check-killswitch-hoist

HOOK_UTILS="lib/hook-utils.sh"

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

LAUNCHERS=("run-guards.sh" "run-python-hook.sh" "prerequisites.sh" "node-or-skip.sh")

is_launcher() {
  local candidate="$1" known
  for known in "${LAUNCHERS[@]}"; do
    [[ "$candidate" == "$known" ]] && return 0
  done
  return 1
}

hooks_dir_of() {
  local rest="${1#plugins/}"
  printf 'plugins/%s/hooks' "${rest%%/*}"
}

scripts_in() {
  local hooks_dir="$1" command="$2" token base skip_next=0
  found=()
  set -f
  # shellcheck disable=SC2086  # deliberate word split: the command is a shell command line
  for token in $command; do
    token="${token%\"}"
    token="${token#\"}"
    if ((skip_next)); then
      skip_next=0
      continue
    fi
    if [[ "$token" == "--lib" || "$token" == "--bps-seed" ]]; then
      skip_next=1
      continue
    fi
    [[ "$token" == *.sh ]] || continue
    base="${token##*/}"
    # shellcheck disable=SC2310  # is_launcher is a pure lookup with no set -e-sensitive body; a false return is the intended "not a launcher"
    is_launcher "$base" && continue
    found+=("$hooks_dir/$base")
  done
  set +f
}

guards=()
unscanned=()
for source in ${HOOK_CONFIG_SOURCES[@]+"${HOOK_CONFIG_SOURCES[@]}"}; do
  hooks_json="${source%%$'\t'*}"
  map="${source#*$'\t'}"
  hooks_dir="$(hooks_dir_of "$hooks_json")"
  while IFS= read -r command; do
    [[ -n "$command" ]] || continue
    scripts_in "$hooks_dir" "$command"
    if ((${#found[@]} == 0)); then
      unscanned+=("$hooks_json")
      continue
    fi
    guards+=("${found[@]}")
  done < <(jq -r --argjson m "$map" '
    (getpath($m) // {}) | (.PreToolUse[]?, .PostToolUse[]?) | .hooks[]?
    | select(.command | type == "string")
    | [.command] + ((.args // []) | map(tostring)) | join(" ")
  ' "$hooks_json")
done

SYNC_ONLY_EVENTS=" UserPromptSubmit UserPromptExpansion PreModelSwitch MessageDisplay "
blocking=()
unreadable=()
for source in ${HOOK_CONFIG_SOURCES[@]+"${HOOK_CONFIG_SOURCES[@]}"}; do
  hooks_json="${source%%$'\t'*}"
  map="${source#*$'\t'}"
  hooks_dir="$(hooks_dir_of "$hooks_json")"
  if ! rows="$(jq -r --argjson m "$map" '(getpath($m) // {}) | to_entries[] | .key as $e | .value[]? | .hooks[]?
    | select(.command | type == "string")
    | [$e, (.async == true | tostring),
        ([.command] + ((.args // []) | map(tostring)) | join(" "))] | @tsv' "$hooks_json" 2>/dev/null)"; then
    unreadable+=("$hooks_json")
    continue
  fi
  while IFS=$'\t' read -r event async command; do
    command="${command%$'\r'}"
    [[ -n "$command" ]] || continue
    [[ "$async" == true && "$SYNC_ONLY_EVENTS" != *" $event "* ]] && continue
    scripts_in "$hooks_dir" "$command"
    if ((${#found[@]} == 0)); then
      unscanned+=("$hooks_json")
      continue
    fi
    blocking+=("${found[@]}")
  done <<<"$rows"
done

if ((${#guards[@]} == 0 && ${#blocking[@]} == 0)); then
  echo "check-killswitch-hoist: no shell hook scripts found on any event — refusing to report clean" >&2
  exit 1
fi

if ((${#guards[@]} > 0)); then
  mapfile -t guards < <(printf '%s\n' "${guards[@]}" | sort -u)
fi
if ((${#blocking[@]} > 0)); then
  mapfile -t blocking < <(printf '%s\n' "${blocking[@]}" | LC_ALL=C sort -u)
fi

SWITCH_RE='^\[\[ "\$\{CLAUDE_PLUGIN_OPTION_[A-Z0-9_]+_ENABLED:-(true|false)\}" == "(true|false)" \]\] (\|\| exit 0|&& exit 0)$'
SOURCE_RE='^[[:space:]]*(source|\.)[[:space:]]+'

# shellcheck disable=SC2016  # a template for the reader to paste, meant literally
HOIST_TEMPLATE='    [[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0'

violations=0

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
