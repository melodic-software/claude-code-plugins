#!/usr/bin/env bash

set -uo pipefail

start=${EPOCHREALTIME:-}

[[ "${CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary cli-flag-verify PostToolUse open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::ctx_reset

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
VERIFIER="$PLUGIN_ROOT/lib/verification/verify-cli-flag.sh"

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PostToolUse" guardrails "$INPUT"

FILE=""
hook::read_file_path_to FILE "$INPUT" || exit 0
IS_MD=false
case "$FILE" in
*.md) IS_MD=true ;;
*.sh | *.bash | *.ps1 | *.psm1) ;;
*) exit 0 ;;
esac

hook::jq_fields "$INPUT" '.tool_name' '.tool_input.new_string' '.tool_input.content' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
case "$TOOL" in
Edit) SCAN_CONTENT="${HOOK_JQ_FIELDS[1]}" ;;
Write) SCAN_CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

CFV_SHARED="$PLUGIN_ROOT/lib/verification/cli-flag-cache.sh"
if [[ ! -x "$VERIFIER" || ! -f "$CFV_SHARED" ]]; then
  if hook::notice_once "guardrails-cli-flag-verifier" "$INPUT"; then
    if [[ ! -x "$VERIFIER" ]]; then
      echo "cli-flag-verify: bundled verifier missing at $VERIFIER" >&2
    else
      echo "cli-flag-verify: bundled verifier library missing at $CFV_SHARED" >&2
    fi
    hook::emit_skip_notice PostToolUse "" \
      "guardrails: cli-flag-verify is off: its bundled verifier is missing. Reinstall guardrails."
  fi
  exit 0
fi

FILE_DIR="${FILE%/*}"
[[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR="."
[[ -n "$FILE_DIR" ]] || FILE_DIR=/
REPO_ROOT="" REPO_ROOT_RESOLVED=1
hook::repo_root_to REPO_ROOT "$FILE_DIR" || REPO_ROOT_RESOLVED=0

DEFAULT_BINS="claude gh dotnet docker kubectl terraform az aws"
BINS_RAW="${CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS:-$DEFAULT_BINS}"
BINS="${BINS_RAW//,/ }"

SKIP_RAW="${CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS:-}"
SKIP="${SKIP_RAW//,/ }"

is_skipped() {
  local bin="$1" skip
  for skip in $SKIP; do
    [[ "$bin" == "$skip" ]] && return 0
  done
  return 1
}

emit_fragments() {
  if [[ "$IS_MD" == "true" ]]; then
    # Inline-code spans (strip the delimiting backticks).
    # shellcheck disable=SC2016  # backticks are literal ERE/sed data, not expansions
    printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null | sed -E 's/^`+//; s/`+$//'
    printf '%s' "$SCAN_CONTENT" | awk '
      /^[[:space:]]*```/ { f = !f; next }
      /^[[:space:]]*~~~/ { f = !f; next }
      f && $0 !~ /^[[:space:]]*#/ { print }
    ' 2>/dev/null
  else
    printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*#' 2>/dev/null || true
  fi
}

split_segments() {
  sed -E 's/\$\(/\n/g; s/(\|\||&&|[;|&`()])/\n/g'
}

declare -A CANDIDATES=()

extract_candidates() {
  local seg
  while IFS= read -r seg; do
    local -a toks=()
    read -ra toks <<<"$seg"
    ((${#toks[@]})) || continue

    local idx=0 lead
    while ((idx < ${#toks[@]})); do
      lead="${toks[idx]#[\`\'\"\(\!]}"
      case "$lead" in
      sudo | command | env | time | exec | xargs | then | do | else | "!")
        ((idx++))
        continue
        ;;
      *)
        if [[ "$lead" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          ((idx++))
          continue
        fi
        break
        ;;
      esac
    done
    ((idx < ${#toks[@]})) || continue

    local bin="${toks[idx]}"
    bin="${bin#[\`\'\"\(\!]}"
    bin="${bin%[\`\'\"\):;,]}"
    [[ " $BINS " == *" $bin "* ]] || continue
    is_skipped "$bin" && continue

    local -a chain=() seg_flags=()
    local chain_done=0 k tk fl ct q="" bare dq sq
    for ((k = idx + 1; k < ${#toks[@]}; k++)); do
      tk="${toks[k]}"
      bare="${tk//\\\\/}"
      bare="${bare//\\\"/}"
      if [[ -n "$q" ]]; then
        [[ "$bare" == *"$q"* ]] && q=""
        continue
      fi
      dq="${bare//[^\"]/}"
      sq="${bare//[^\']/}"
      if [[ "$tk" == [\"\']* ]]; then
        if [[ "$tk" == \"* ]]; then
          ((${#dq} % 2)) && q='"'
        else
          ((${#sq} % 2)) && q="'"
        fi
        continue
      fi
      if ((${#dq} % 2)); then
        q='"'
      elif ((${#sq} % 2)); then
        q="'"
      fi
      case "$tk" in
      --)
        break
        ;;
      --*)
        chain_done=1
        fl="${tk%%=*}"
        if [[ "$fl" =~ ^(--[a-zA-Z][a-zA-Z0-9-]*) ]]; then
          fl="${BASH_REMATCH[1]}"
          case "$fl" in
          --help | --version) ;;
          *) seg_flags+=("$fl") ;;
          esac
        fi
        ;;
      -?*)
        ((chain_done == 0 && ${#chain[@]} > 0)) && chain_done=1
        ;;
      *)
        ct="${tk%[\`\'\"\):;,]}"
        ct="${ct#[\`\'\"\(]}"
        [[ " $BINS " == *" $ct "* ]] && break
        if ((chain_done == 0)) && [[ "$ct" =~ ^[a-z][a-z0-9-]*$ ]] && ((${#chain[@]} < 4)); then
          chain+=("$ct")
        fi
        ;;
      esac
    done

    ((${#seg_flags[@]})) || continue
    local chainstr="${chain[*]}" f
    for f in "${seg_flags[@]}"; do
      CANDIDATES["$bin|$chainstr|$f"]=1
    done
  done < <(emit_fragments | split_segments)
}

HAS_FLAG_SHAPE=0
[[ "$SCAN_CONTENT" == *-* ]] && HAS_FLAG_SHAPE=1

HAS_BIN=0
for cfv_bin in $BINS; do
  if [[ "$SCAN_CONTENT" == *"$cfv_bin"* ]]; then
    HAS_BIN=1
    break
  fi
done

((HAS_FLAG_SHAPE && HAS_BIN)) && extract_candidates

reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  ((${#CANDIDATES[@]} == 0)) || return 0
  local -a hunk_flags=()
  mapfile -t hunk_flags < <(
    printf '%s' "$SCAN_CONTENT" |
      grep -oE '(^|[[:space:]])--?[A-Za-z0-9][A-Za-z0-9-]*' 2>/dev/null |
      sed -E 's/^[[:space:]]*//' | sort -u
  )
  ((${#hunk_flags[@]})) || return 0
  local tok ctx="" lines
  for tok in "${hunk_flags[@]}"; do
    lines=$(grep -F -- "$tok" "$FILE" 2>/dev/null)
    [[ -n "$lines" ]] && ctx+="$lines"$'\n'
  done
  ctx=$(printf '%s' "$ctx" | grep -vE '^[[:space:]]*$' | head -20)
  [[ -n "$ctx" ]] || return 0
  SCAN_CONTENT="$ctx"
  extract_candidates
  local key flag t keep
  for key in "${!CANDIDATES[@]}"; do
    flag="${key##*|}"
    keep=0
    for t in "${hunk_flags[@]}"; do
      [[ "$flag" == "$t" ]] && {
        keep=1
        break
      }
    done
    ((keep)) || unset 'CANDIDATES[$key]'
  done
}

((HAS_FLAG_SHAPE)) && reconstruct_partial_edit

KEY_BIN=""
KEY_CHAIN=""
KEY_FLAG=""
KEY_DISP=""
KEY_HELPREF=""
split_candidate_key() {
  local rest
  KEY_BIN="${1%%|*}"
  rest="${1#*|}"
  KEY_CHAIN="${rest%|*}"
  KEY_FLAG="${rest##*|}"
  if [[ -n "$KEY_CHAIN" ]]; then
    KEY_DISP="$KEY_BIN $KEY_CHAIN $KEY_FLAG"
    KEY_HELPREF="$KEY_BIN $KEY_CHAIN --help"
  else
    KEY_DISP="$KEY_BIN $KEY_FLAG"
    KEY_HELPREF="$KEY_BIN --help"
  fi
}

CFV_CACHE_DIR=""
declare -A CFV_FRESH=()
CFV_FRESH_INDEXED=0
cfv_index_fresh_cache() {
  local f
  ((CFV_FRESH_INDEXED)) && return 0
  CFV_FRESH_INDEXED=1
  # shellcheck source=../lib/verification/cli-flag-cache.sh
  source "$CFV_SHARED"
  cfv_cache_dir_to CFV_CACHE_DIR
  [[ -d "$CFV_CACHE_DIR" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] && CFV_FRESH["$f"]=1
  done < <(find "$CFV_CACHE_DIR" -maxdepth 1 -name '*.help' -mmin "-$CFV_CACHE_WINDOW_MIN" 2>/dev/null)
}
verify_candidate() {
  local bin="$1" chainstr="$2" flag="$3" key cache_file help rc global
  local -a chainarr=()
  read -ra chainarr <<<"$chainstr"
  cfv_index_fresh_cache
  cfv_cache_key_to key "$bin" "${chainarr[@]}"
  cache_file="$CFV_CACHE_DIR/$key.help"
  if [[ -n "${CFV_FRESH[$cache_file]:-}" && -s "$cache_file" ]]; then
    help=$(<"$cache_file")
    cfv_flag_in_help "$help" "$flag" && return 0
    cfv_global_chain_to global "$bin"
    [[ -n "$global" && "$chainstr" != "$global" ]] && verify_candidate "$bin" "$global" "$flag" && return 0
    return 1
  fi
  "$VERIFIER" --quiet "$bin" "${chainarr[@]}" "$flag" 2>/dev/null
  rc=$?
  if ((rc == 0 || rc == 1)) && [[ -s "$cache_file" ]]; then
    CFV_FRESH["$cache_file"]=1
  fi
  return "$rc"
}

FAILURES=()
for key in "${!CANDIDATES[@]}"; do
  split_candidate_key "$key"
  command -v "$KEY_BIN" >/dev/null 2>&1 || continue
  verify_candidate "$KEY_BIN" "$KEY_CHAIN" "$KEY_FLAG"
  rc=$?
  if [[ "$rc" -eq 1 ]]; then
    FAILURES+=("$key")
  fi
done

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local findings_json="[]" file_rel
  file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "$REPO_ROOT"
  if ((${#FAILURES[@]} > 0)); then
    local f raw=""
    for f in "${FAILURES[@]}"; do
      split_candidate_key "$f"
      raw+="$KEY_DISP"$'\n'
    done
    findings_json=$(printf '%s' "$raw" | jq -Rn '[inputs]' 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "cli-flag-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#FAILURES[@]} > 0)); then
  show_file="$FILE"
  ((REPO_ROOT_RESOLVED)) && [[ "$FILE" == "${REPO_ROOT%/}/"?* ]] && show_file="${FILE#"${REPO_ROOT%/}/"}"
  lines=""
  for f in "${FAILURES[@]}"; do
    split_candidate_key "$f"
    lines+="$KEY_DISP (not in '$KEY_HELPREF')"$'\n'
  done
  cfv_ctx=""
  hook::findings_to cfv_ctx \
    "cli-flag-verify: unknown flag(s) in $show_file, unverified, not proven wrong: the installed --help may predate the flag." \
    "$lines" --max 10
  hook::ctx_append "$cfv_ctx"
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
