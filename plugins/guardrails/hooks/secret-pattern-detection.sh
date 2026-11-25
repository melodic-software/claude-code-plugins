#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary secret-pattern-detection PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
# shellcheck source=../lib/secret-detection/secret-patterns.sh
source "$PLUGIN_ROOT/lib/secret-detection/secret-patterns.sh"

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" \
  '.tool_name' '.tool_input.file_path' \
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source' \
  '.tool_input.path' '.tool_input.notebook_path' || exit 0

secret_nul_refusal() {
  guard::refuse_nul
  exit 2
}

SECRET_FIX="Remove the value; use an environment variable, settings.local.json or a secret manager. For a test fixture, ask the user."

if ((HOOK_JQ_FIELDS_NUL)); then
  secret_nul_refusal
fi

TOOL="${HOOK_JQ_FIELDS[0]}"

secret_path_allowlisted() {
  case "$1" in
  *.claude/hooks/*) return 0 ;;
  *settings.local.json) return 0 ;;
  *CLAUDE.local.md) return 0 ;;
  */.venv/* | .venv/*) return 0 ;;
  */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *.claude/skills/*/context/*) return 0 ;;
  *.claude/skills/*/completed/*) return 0 ;;
  *) return 1 ;;
  esac
}

# Call as: secret_scan <content> -> $scan_out $labels
# shellcheck disable=SC2154  # scan_out and labels are the caller's frame, per the call contract
secret_scan() {
  local line
  scan_out=""
  secrets::any_match "$1" || return 0
  scan_out=$(
    secrets::scan_text "$1"
    printf x
  )
  scan_out=${scan_out%x}
  [[ -n "$scan_out" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    labels+=("${line%% (line *}")
  done < <(printf '%s' "$scan_out")
}

spd_send_tel() {
  local data
  data=$(jq -n --arg file "$2" --argjson violations "$3" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "secret-pattern-detection" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

mcp_lane() {
  local count=1 i path content violations="" first_offender="" scan_out
  local -a labels=()
  local single_path="${HOOK_JQ_FIELDS[5]}" single_content="${HOOK_JQ_FIELDS[2]}"

  if [[ "$TOOL" == *__push_files ]]; then
    hook::jq_fields "$INPUT" '.tool_input.files | length' || return 0
    count="${HOOK_JQ_FIELDS[0]}"
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
  fi

  for ((i = 0; i < count; i++)); do
    if [[ "$TOOL" == *__push_files ]]; then
      hook::jq_fields "$INPUT" ".tool_input.files[$i].path" ".tool_input.files[$i].content" || continue
      path="${HOOK_JQ_FIELDS[0]}"
      content="${HOOK_JQ_FIELDS[1]}"
    else
      path="$single_path"
      content="$single_content"
    fi

    if ((HOOK_JQ_FIELDS_NUL)); then
      secret_nul_refusal
    fi

    [[ -n "$path" && -n "$content" ]] || continue
    secret_path_allowlisted "${path//\\//}" && continue

    secret_scan "$content"
    [[ -n "$scan_out" ]] || continue

    [[ -n "$first_offender" ]] || first_offender="$path"
    violations+="$path:"$'\n'"$scan_out"$'\n'
  done

  [[ -n "$violations" ]] || return 0

  {
    printf 'BLOCKED: secret/credential pattern(s) in content bound for GitHub:\n\n'
    printf '%s\n' "$violations"
    printf '%s\n' "$SECRET_FIX"
  } >&2

  if [[ -n "$start" ]] && hook::telemetry_enabled; then
    local labels_json
    labels_json=$(printf '%s\n' "${labels[@]}" | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
    spd_send_tel "blocked" "$first_offender" "$labels_json"
  fi
  exit 2
}

case "$TOOL" in
Write | Edit | NotebookEdit) ;;
mcp__github__push_files | mcp__github__create_or_update_file | \
  mcp__plugin_*_github__push_files | mcp__plugin_*_github__create_or_update_file)
  mcp_lane
  exit 0
  ;;
*) exit 0 ;;
esac

FILE="${HOOK_JQ_FIELDS[1]}"
[[ "$TOOL" == NotebookEdit && -n "${HOOK_JQ_FIELDS[6]}" ]] && FILE="${HOOK_JQ_FIELDS[6]}"
[[ -n "$FILE" ]] || exit 0

NORM_FILE=""
hook::normalize_path_to NORM_FILE "$FILE"

ALLOW_FILE="${FILE//\\//}"

spd_scope_root="${CLAUDE_PROJECT_DIR:-}"
spd_scope_root="${spd_scope_root//\\//}"
PROJECT_DIR=""
if [[ -n "$spd_scope_root" ]]; then
  spd_keep=1
  case "$spd_scope_root" in
  *//* | */./* | */../* | */. | */.. | *~*) spd_keep=0 ;;
  /* | [A-Za-z]:/*) ;;
  *) spd_keep=0 ;;
  esac
  spd_scope_root="${spd_scope_root%/}"
  if ((spd_keep)); then
    spd_keep=0
    if [[ -e "$spd_scope_root/.git/HEAD" ]]; then
      spd_keep=1
    elif [[ -f "$spd_scope_root/.git" ]]; then
      spd_gitline=""
      { IFS= read -r spd_gitline <"$spd_scope_root/.git"; } 2>/dev/null || :
      [[ "$spd_gitline" == gitdir:* ]] && spd_keep=1
    fi
  fi
  hook::normalize_path_to PROJECT_DIR "$spd_scope_root"
  spd_home=""
  hook::normalize_path_to spd_home "${HOME:-${USERPROFILE:-}}"
  [[ -z "$spd_home" || "$spd_home/" == "$PROJECT_DIR"/* ]] && spd_keep=0
  spd_prev=""
  for spd_h in "${HOME:-}" "${USERPROFILE:-}"; do
    ((spd_keep)) || break
    [[ -n "$spd_h" && "$spd_h" != "$spd_prev" ]] || continue
    spd_prev="$spd_h"
    spd_h="${spd_h//\\//}"
    spd_h="${spd_h%/}"
    while [[ "$spd_h" == */* ]]; do
      if [[ "$spd_scope_root" -ef "$spd_h" ]]; then
        spd_keep=0
        break
      fi
      spd_h="${spd_h%/*}"
    done
  done
  if ((spd_keep == 0)); then
    spd_scope_root=""
    PROJECT_DIR=""
  fi
fi
if [[ -n "$PROJECT_DIR" ]]; then
  case "$NORM_FILE" in
  "$PROJECT_DIR"/*) ;;
  *) exit 0 ;;
  esac
fi

secret_path_allowlisted "$ALLOW_FILE" && exit 0


spd_win=0
case "${OSTYPE:-}" in
msys* | cygwin* | win32) spd_win=1 ;;
*) ;;
esac

if ((BASH_VERSINFO[0] >= 4)); then
  eval 'spd_lower_to() { printf -v "$1" "%s" "${2,,}"; }'
fi

spd_under_temp() {
  local lower
  hook::under_temp_root "$1" || return 1
  ((spd_win)) && return 0
  if ((BASH_VERSINFO[0] < 4)); then
    [[ "$1" != *[[:upper:]]* ]]
    return
  fi
  spd_lower_to lower "$1"
  hook::under_temp_root "$lower"
}

spd_ancestor=""
spd_sfx=""
spd_nearest_existing() {
  local p="$1" prev=""
  spd_ancestor=""
  spd_sfx=""
  while [[ -n "$p" && "$p" != "$prev" ]]; do
    if [[ -e "$p" || -L "$p" ]]; then
      spd_ancestor="$p"
      return 0
    fi
    prev="$p"
    spd_sfx="/${p##*/}$spd_sfx"
    p="${p%/*}"
  done
  spd_sfx=""
  return 1
}

spd_one_link() {
  local links
  [[ -f "$1" ]] || return 0
  links=$(stat -L -c %h -- "$1" 2>/dev/null) || links=$(stat -L -f %l -- "$1" 2>/dev/null) || return 1
  [[ "$links" == 1 ]]
}

spd_short_re='^([A-Za-z0-9_-]+~[1-9][0-9]*)(\.[A-Za-z0-9_-]{1,3})?$'
spd_short_spelling() {
  local rest="$1" comp
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    [[ "$comp" == *'~'* ]] || continue
    [[ "$comp" =~ $spd_short_re ]] || return 1
    ((${#BASH_REMATCH[1]} <= 8)) || return 1
  done
  return 0
}

spd_temp_declines() {
  local t="$1" r="${CLAUDE_PROJECT_DIR:-}" cand norm hit=0 nocase=0 ranc="" rsfx phys
  local short=0 chars full custom
  if ((spd_win)); then
    t="${t//\\//}"
    r="${r//\\//}"
    [[ "$t" == [A-Za-z]:/?* ]] || return 1
  else
    [[ "$t$r" == *\\* || "$t" != /?* ]] && return 1
    ((BASH_VERSINFO[0] >= 4)) || [[ "$t" != *[[:upper:]]* ]] || return 1
  fi
  chars="$t"
  if [[ "$t" == *'~'* ]]; then
    ((spd_win)) || return 1
    spd_short_spelling "$t" || return 1
    short=1
    chars="${t//\~/}"
  fi
  [[ "$chars" == *[!A-Za-z0-9._/:+,=@%-]* ]] && return 1
  case "$t" in
  *//* | */./* | */../* | */. | */..) return 1 ;;
  *) ;;
  esac
  full=$short
  shopt -q nocasematch && nocase=1
  shopt -s nocasematch
  while :; do
    if ((full)); then hook::_temp_root_candidates; else hook::_temp_root_candidates --no-drive; fi
    if ((!short)); then
      case "$t" in
      */tmp/* | */temp/*) hit=1 ;;
      *) ;;
      esac
    fi
    custom=0
    for cand in ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}; do
      case "$cand" in
      */tmp | */tmp/* | */temp | */temp/*) ;;
      *) custom=1 ;;
      esac
      ((hit)) && continue
      hook::normalize_path_to norm "$cand"
      norm="${norm%/}"
      [[ -n "$norm" && "$t" == "$norm"/* ]] && hit=1
    done
    ((hit || full || !spd_win || !custom)) && break
    full=1
  done
  ((nocase)) || shopt -u nocasematch
  ((hit)) || return 1
  if ((spd_win && !full)); then hook::_temp_root_candidates; fi
  [[ -n "$r" ]] || return 1
  case "$r" in
  *'$'* | *'`'* | *~* | *'*'* | *'?'* | *'['* | *//* | */./* | */../* | */. | */..) return 1 ;;
  *) ;;
  esac
  if ((spd_win)); then
    [[ "$r" == /?* || "$r" == [A-Za-z]:/?* ]] || return 1
  else
    [[ "$r" == /?* ]] || return 1
  fi
  r="${r%/}"
  ((spd_win)) && [[ "$r" == /[A-Za-z] ]] && return 1
  spd_nearest_existing "$r" && ranc="$spd_ancestor"
  rsfx="$spd_sfx"
  hook::_physical_prime ${ranc:+"$ranc"} ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}
  hook::under_temp_root "$r" && return 1
  if [[ -n "$ranc" ]]; then
    hook::_physical_cached_to phys "$ranc" || return 1
    hook::under_temp_root "${phys%/}$rsfx" && return 1
  fi
  ((short)) || spd_under_temp "$t" || return 1
  spd_one_link "$t" || return 1
  spd_nearest_existing "$t" || return 1
  hook::physical_path_to phys "$spd_ancestor" || return 1
  if ((short)); then
    case "${phys%/}$spd_sfx" in
    *'$'* | *'`'* | *'~'* | *'*'* | *'?'* | *'['*) return 1 ;;
    *) ;;
    esac
  fi
  spd_under_temp "${phys%/}$spd_sfx"
}
spd_temp_declines "$FILE" && exit 0

case "$TOOL" in
Write) CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
Edit) CONTENT="${HOOK_JQ_FIELDS[3]}" ;;
NotebookEdit) CONTENT="${HOOK_JQ_FIELDS[4]}" ;;
*) exit 0 ;;
esac
[[ -n "$CONTENT" ]] || exit 0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel root="$spd_scope_root"
  local file_dir="${FILE%/*}"
  [[ "$file_dir" == "$FILE" ]] && file_dir="."
  [[ -n "$file_dir" ]] || file_dir=/
  [[ -n "$root" ]] || hook::repo_root_to root "$file_dir"
  root="${root%/}"
  file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "$root"
  spd_send_tel "$1" "$file_rel" "$2"
}

labels=()
scan_out=""
secret_scan "$CONTENT"
if [[ -z "$scan_out" ]]; then
  emit_tel "ok" '[]'
  exit 0
fi


spd_et=""
spd_exempt_target() {
  local t="$1"
  spd_et=""
  if ((spd_win)); then
    t="${t//\\//}"
    [[ "$t" == [A-Za-z]:/?* ]] || return 1
  else
    [[ "$t" == /?* && "$t" != *\\* ]] || return 1
  fi
  case "$t" in
  *//* | */./* | */../* | */. | */.. | *[$'\n\r']*) return 1 ;;
  *) ;;
  esac
  spd_one_link "$t" || return 1
  spd_et="$t"
}

spd_exempt_anchor() {
  if ! spd_nearest_existing "$1"; then
    [[ "$1" == /* ]] || return 1
    spd_ancestor=/
    spd_sfx="$1"
  fi
  [[ "$spd_ancestor" =~ ^[A-Za-z]:$ ]] && spd_ancestor+=/
  return 0
}

spd_cmp_to() {
  local __sc_p="$2"
  [[ "$__sc_p" != *[$'\n\r']* ]] || return 1
  if ((spd_win)); then
    if [[ ! "$__sc_p" =~ ^(/[A-Za-z]/|[A-Za-z]:/) ]]; then
      __sc_p=$(cygpath -l -m -- "$__sc_p" 2>/dev/null) || return 1
      [[ -n "$__sc_p" ]] || return 1
    fi
  else
    [[ "$__sc_p" != *\\* ]] || return 1
  fi
  hook::normalize_path_to __sc_p "$__sc_p"
  [[ "$__sc_p" == / ]] || __sc_p="${__sc_p%/}"
  printf -v "$1" '%s' "$__sc_p"
}

spd_canon_to() {
  local __sc_r
  hook::_physical_cached_to __sc_r "$2" || return 1
  [[ "$__sc_r" -ef "$2" ]] || return 1
  spd_cmp_to "$1" "$__sc_r"
}

spd_under_allowed_root() {
  local roots="$spd_opt_roots" c r h a t phys held
  local -a cand=() homes=()
  while [[ -n "$roots" ]]; do
    c="${roots%%,*}"
    if [[ "$c" == "$roots" ]]; then roots=""; else roots="${roots#*,}"; fi
    [[ "$c" != *[$'\n\r']* ]] || continue
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    c="${c//\\//}"
    [[ -n "$c" && "$c" != *[*?[]* && "$c" != //* && "/$c/" != */../* ]] || continue
    [[ "$c" == / || "$c" =~ ^([A-Za-z]:|/[A-Za-z])/?$ ]] && continue
    if ((spd_win)); then
      [[ "$c" == /* || "$c" =~ ^[A-Za-z]:/ ]] || continue
    else
      [[ "$c" == /* ]] || continue
    fi
    [[ -d "$c" ]] && cand+=("$c")
  done
  ((${#cand[@]})) || return 1
  for h in "${HOME:-}" "${USERPROFILE:-}"; do
    [[ -n "$h" ]] && homes+=("${h//\\//}")
  done
  ((${#homes[@]})) || return 1
  hook::_physical_prime "${cand[@]}" "${homes[@]}"
  local -a held_homes=()
  for h in "${homes[@]}"; do
    [[ ("$h" == /* || "$h" =~ ^[A-Za-z]:/) && -d "$h" ]] || return 1
    spd_canon_to held "$h" || return 1
    held_homes+=("$held")
  done
  spd_exempt_anchor "$spd_et" || return 1
  hook::physical_path_to phys "$spd_ancestor" || return 1
  [[ "$phys" -ef "$spd_ancestor" ]] || return 1
  spd_cmp_to t "$phys" || return 1
  spd_cmp_to t "${t%/}$spd_sfx" || return 1
  for c in "${cand[@]}"; do
    spd_canon_to r "$c" || continue
    [[ "$r" == / || "$r" =~ ^[A-Za-z]:/?$ || "$r" =~ ^/[A-Za-z]$ ]] && continue
    for h in "${held_homes[@]}"; do
      [[ "$h" == "$r" || "$h" == "$r"/* ]] && continue 2
    done
    for h in "${homes[@]}"; do
      a="${h%/}"
      while [[ "$a" == */* ]]; do
        [[ "$c" -ef "$a" ]] && continue 3
        a="${a%/*}"
      done
    done
    [[ "$t" == "$r"/* ]] && return 0
  done
  return 1
}

spd_gitignored() {
  local t="$1" d base rel
  [[ ! -L "$t" ]] || return 1
  command -v git >/dev/null 2>&1 || return 1
  d="${t%/*}" base="${t##*/}"
  [[ -n "$base" ]] || return 1
  spd_exempt_anchor "${d:-/}" || return 1
  [[ -d "$spd_ancestor" ]] || return 1
  rel=".$spd_sfx/$base"
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX GIT_CONFIG \
      GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
    cd "$spd_ancestor" 2>/dev/null || exit 1
    hook::git_untrusted check-ignore -q -- "$rel" 2>/dev/null
  )
}

spd_opt_roots="${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ALLOWED_ROOTS:-}"
spd_opt_ignored="${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_SKIP_GITIGNORED:-false}"
if [[ -n "$spd_opt_roots" || "$spd_opt_ignored" == true ]] && spd_exempt_target "$FILE"; then
  [[ -n "$spd_opt_roots" ]] && spd_under_allowed_root && exit 0
  [[ "$spd_opt_ignored" == true ]] && spd_gitignored "$spd_et" && exit 0
fi

show_file="$FILE"
_spd_proj="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$_spd_proj" && "$FILE" == "${_spd_proj%/}/"?* ]] && show_file="${FILE#"${_spd_proj%/}/"}"
{
  printf 'BLOCKED: secret/credential pattern(s) in %s:\n\n' "$show_file"
  printf '%s\n' "$scan_out"
  printf '%s\n' "$SECRET_FIX"
} >&2
labels_json=$(printf '%s\n' "${labels[@]}" | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
emit_tel "blocked" "$labels_json"
exit 2
