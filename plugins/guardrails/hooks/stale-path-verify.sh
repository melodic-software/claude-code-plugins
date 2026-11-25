#!/usr/bin/env bash

set -uo pipefail

start=${EPOCHREALTIME:-}

[[ "${CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary stale-path-verify PostToolUse open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::ctx_reset

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PostToolUse" guardrails "$INPUT"

FILE=""
hook::read_file_path_to FILE "$INPUT" || exit 0
case "$FILE" in
*/CHANGELOG.md | CHANGELOG.md) exit 0 ;;
*.md) ;;
*) exit 0 ;;
esac

hook::jq_fields "$INPUT" '.tool_name' '.tool_input.new_string' \
  '.tool_input.content' '.tool_input.replace_all // false | tostring' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
REPLACE_ALL=false
case "$TOOL" in
Edit)
  SCAN_CONTENT="${HOOK_JQ_FIELDS[1]}"
  REPLACE_ALL="${HOOK_JQ_FIELDS[3]}"
  case "$REPLACE_ALL" in
  true | false) ;;
  *)
    exit 0
    ;;
  esac
  ;;
Write) SCAN_CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

FILE_DIR="${FILE%/*}"
[[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR="."
[[ -n "$FILE_DIR" ]] || FILE_DIR=/
REPO_ROOT=""
hook::repo_root_to REPO_ROOT "$FILE_DIR"
[[ -d "$REPO_ROOT" ]] || exit 0

emit_tokens() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//'
}

# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__plain() { [[ "$1" != *[![:print:][:space:]]* ]]; }
spv_plain() { hook::_c_locale spv__plain "$1"; }
# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__word_anchor() { [[ "$1" != *' '* && "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
spv_word_occurrences() {
  HOOK_ANCHOR="$1" LC_ALL=C awk '
    BEGIN { a = ENVIRON["HOOK_ANCHOR"]; n = 0 }
    {
      k = split($0, w, /[^A-Za-z0-9_]+/)
      for (j = 1; j <= k; j++) if (w[j] == a) n++
    }
    END { print n + 0 }
  ' "$2"
}

spv_anchor_occurrences() {
  local anchor="$1" file="$2" line rest prefix n=0
  [[ -n "$anchor" && -f "$file" ]] || {
    printf '0'
    return 0
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    rest=$line
    while [[ -n "$rest" ]]; do
      prefix=${rest%%"$anchor"*}
      [[ "$prefix" == "$rest" ]] && break
      n=$((n + 1))
      rest=${rest:$((${#prefix} + 1))}
    done
  done <"$file"
  printf '%s' "$n"
}

# spv__lines <text>: SPV_LINES = <text>'s non-empty lines.
# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__lines() {
  local IFS=$'\n' noglob=0
  [[ $- == *f* ]] && noglob=1
  set -f
  # shellcheck disable=SC2206 # splitting on newlines is the intent
  SPV_LINES=($1)
  ((noglob)) || set +f
}

# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__spans() {
  SPV_OUT=()
  local line rest tok
  [[ "$1" == *'`'*'`'* ]] || return 0
  spv__lines "$1"
  for line in ${SPV_LINES[@]+"${SPV_LINES[@]}"}; do
    rest=$line
    while [[ "$rest" == *'`'*'`'* ]]; do
      rest=${rest#*'`'}
      tok=${rest%%'`'*}
      [[ -n "$tok" ]] || continue
      SPV_OUT+=("$tok")
      rest=${rest#*'`'}
    done
  done
}

# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__residue_tokens() {
  SPV_OUT=()
  local line rest out w
  local -A seen=()
  local -a words=()
  spv__lines "$1"
  for line in ${SPV_LINES[@]+"${SPV_LINES[@]}"}; do
    out="" rest=$line
    while [[ "$rest" == *'`'*'`'* ]]; do
      out+=${rest%%'`'*}
      rest=${rest#*'`'}
      rest=${rest#*'`'}
    done
    out+=$rest
    out=${out//[^A-Za-z0-9._-]/ }
    IFS=' ' read -r -a words <<<"$out"
    for w in ${words[@]+"${words[@]}"}; do
      w=${w#"${w%%[A-Za-z0-9]*}"}
      ((${#w} >= 2)) || continue
      [[ -n "${seen[$w]:-}" ]] && continue
      seen[$w]=1
      SPV_OUT+=("$w")
    done
  done
}

# `grep -vE '^[[:space:]]*$' | head -<max>`: the non-blank lines, at most <max>.
# shellcheck disable=SC2329 # reached through hook::_c_locale
spv__nonblank() {
  SPV_OUT=()
  local line
  spv__lines "$1"
  for line in ${SPV_LINES[@]+"${SPV_LINES[@]}"}; do
    [[ "$line" == *[![:space:]]* ]] || continue
    SPV_OUT+=("$line")
    ((${#SPV_OUT[@]} < ${2:-2147483647})) || break
  done
}

spv_tokens() {
  if spv_plain "$SCAN_CONTENT"; then
    hook::_c_locale spv__spans "$SCAN_CONTENT"
  else
    mapfile -t SPV_OUT < <(emit_tokens)
  fi
}

TRACKED_FILES=""
TRACKED_BUILT=0
ensure_tracked_files() {
  if ((TRACKED_BUILT == 0)); then
    local out git_dir="" index="" cache="" n
    local -a cached_lines=()
    if spv_git_dir_to git_dir; then
      index="$git_dir/index"
      cache="$git_dir/guardrails-ls-files"
    fi
    if [[ -n "$cache" && -f "$cache" && -f "$index" && "$cache" -nt "$index" ]]; then
      mapfile -t cached_lines <"$cache"
      n=$((${#cached_lines[@]} - 1))
      if ((n >= 0)) && [[ "${cached_lines[n]}" == "end $n" ]]; then
        local IFS=$'\n'
        out="${cached_lines[*]:0:n}"
        if [[ $'\n'"$out" != *$'\n'"end "[0-9]* ]]; then
          TRACKED_FILES=$out
          TRACKED_BUILT=1
          return 0
        fi
      fi
    fi
    if out=$(hook::git_untrusted -C "$REPO_ROOT" ls-files 2>/dev/null); then
      TRACKED_FILES=${out//$'\r'/}
      TRACKED_BUILT=1
      if [[ -n "$cache" ]]; then
        n=0
        out=""
        if [[ -n "$TRACKED_FILES" ]]; then
          mapfile -t cached_lines <<<"$TRACKED_FILES"
          n=${#cached_lines[@]}
          out=$TRACKED_FILES$'\n'
        fi
        printf '%send %d\n' "$out" "$n" 2>/dev/null >"$cache" || :
      fi
    fi
  fi
}

# Call as: tracked_basename_matches <base> -> $matches
# shellcheck disable=SC2154  # matches is the caller's frame, per the call contract
tracked_basename_matches() {
  matches=()
  ensure_tracked_files
  [[ -n "$TRACKED_FILES" ]] || return 1
  mapfile -t matches < <(printf '%s\n' "$TRACKED_FILES" | awk -F/ -v b="$1" '$NF == b')
}

root_basename_is_ambiguous() {
  local base="$1"
  local -a matches=()
  case "$base" in
  README.md | README | package.json | package-lock.json | LICENSE | LICENCE | CHANGELOG.md | Makefile | GNUmakefile | .gitignore | .gitattributes | .editorconfig) return 0 ;; # both license-file spellings are matched on purpose # spellchecker:disable-line
  *) ;;
  esac
  tracked_basename_matches "$base" || return 1
  ((${#matches[@]} > 1))
}

normalize_candidate() {
  local t="$1"
  NORM_CAND=""

  [[ "$t" =~ [[:space:]] ]] && return 0

  t="${t%%:[0-9]*}"

  t="${t%%#*}"

  t="${t#[\'\"\(]}"
  t="${t%[\'\"\),;.]}"

  t="${t#./}"

  local is_root=0
  [[ "$t" == */* ]] || is_root=1

  case "$t" in
  *://* | //* | mailto:* | \#*) return 0 ;;
  /* | [A-Za-z]:[/\\]*) return 0 ;;
  '~'*) return 0 ;;
  ../* | */../*) return 0 ;;
  *'*'* | *'?'* | *'['* | *']'* | *'{'* | *'}'* | *'<'* | *'>'* | *'$'* | *'('* | *')'* | *'|'* | *'!'*) return 0 ;;
  *...*) return 0 ;;
  node_modules/* | */node_modules/* | .git/* | */.git/*) return 0 ;;
  *) ;;
  esac

  local last="${t##*/}"
  if ((is_root)); then
    [[ "$last" == *.* ]] || return 0
    root_basename_is_ambiguous "$t" && return 0
  else
    if [[ "$t" != */ && "$last" != *.* ]]; then
      return 0
    fi
  fi

  NORM_CAND=$t
}

spv_fixed_hits() {
  SPV_HITS=()
  local line needle=$1 file=$2
  [[ -f "$file" && -n "$needle" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *"$needle"* ]] && SPV_HITS+=("$line")
  done <"$file"
}

reconstruct_partial_edit() {
  RECON_OUT=()
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  local residue plain=0
  spv_plain "$SCAN_CONTENT" && plain=1
  local -a toks=()
  if ((plain)); then
    hook::_c_locale spv__residue_tokens "$SCAN_CONTENT"
    toks=(${SPV_OUT[@]+"${SPV_OUT[@]}"})
  else
    # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
    residue=$(printf '%s' "$SCAN_CONTENT" | sed -E 's/`[^`]*`//g')
    mapfile -t toks < <(printf '%s' "$residue" | grep -oE '[A-Za-z0-9][A-Za-z0-9._-]{1,}' 2>/dev/null | sort -u)
  fi
  ((${#toks[@]})) || return 0
  local -a anchors=()
  if ((plain)); then
    hook::_c_locale spv__nonblank "$SCAN_CONTENT"
    anchors=(${SPV_OUT[@]+"${SPV_OUT[@]}"})
  else
    mapfile -t anchors < <(printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*$' 2>/dev/null)
  fi
  ((${#anchors[@]})) || return 0
  local anchor occ ctx=""
  local -a hits=()
  for anchor in "${anchors[@]}"; do
    if [[ "$anchor" != *' '* && "$anchor" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      mapfile -t hits < <(grep -w -F -- "$anchor" "$FILE" 2>/dev/null)
    else
      spv_fixed_hits "$anchor" "$FILE"
      hits=(${SPV_HITS[@]+"${SPV_HITS[@]}"})
    fi
    ((${#hits[@]})) || continue
    if [[ "$REPLACE_ALL" == "true" ]]; then
      for occ in "${hits[@]}"; do ctx+="$occ"$'\n'; done
      continue
    fi
    if hook::_c_locale spv__word_anchor "$anchor"; then
      [[ "$anchor" != *[.-]* ]] || continue
      occ=$(spv_word_occurrences "$anchor" "$FILE" 2>/dev/null)
    else
      occ=$(spv_anchor_occurrences "$anchor" "$FILE")
    fi
    ((occ == 1)) || continue
    ctx+="${hits[0]}"$'\n'
  done
  [[ -n "$ctx" ]] || return 0
  local saved="$SCAN_CONTENT" raw cand seg
  if spv_plain "$ctx"; then
    hook::_c_locale spv__nonblank "$ctx" 40
    SCAN_CONTENT=""
    for raw in ${SPV_OUT[@]+"${SPV_OUT[@]}"}; do SCAN_CONTENT+=${SCAN_CONTENT:+$'\n'}$raw; done
  else
    SCAN_CONTENT=$(printf '%s' "$ctx" | grep -vE '^[[:space:]]*$' | head -40)
  fi
  spv_tokens
  for raw in ${SPV_OUT[@]+"${SPV_OUT[@]}"}; do
    [[ -n "$raw" ]] || continue
    normalize_candidate "$raw"
    cand=$NORM_CAND
    [[ -n "$cand" ]] || continue
    for seg in "${toks[@]}"; do
      if [[ "$cand" == *"$seg"* ]]; then
        RECON_OUT+=("$cand")
        break
      fi
    done
  done
  SCAN_CONTENT="$saved"
}

spv_git_dir_to() {
  local g="$REPO_ROOT/.git" line
  if [[ -d "$g" ]]; then
    printf -v "$1" '%s' "$g"
    return 0
  fi
  if [[ -f "$g" ]]; then
    IFS= read -r line <"$g" || return 1
    line=${line%$'\r'}
    [[ "$line" == 'gitdir:'* ]] || return 1
    line=${line#gitdir:}
    line=${line#"${line%%[![:space:]]*}"}
    if [[ "$line" != /* && "$line" != [A-Za-z]:[/\\]* ]]; then
      line="$REPO_ROOT/$line"
    fi
    printf -v "$1" '%s' "$line"
    return 0
  fi
  return 1
}

spv_git_common_to() {
  local line="$2"
  if [[ -f "$2/commondir" ]]; then
    IFS= read -r line <"$2/commondir" || return 1
    line=${line%$'\r'}
    line=${line%"${line##*[![:space:]]}"}
    line=${line#"${line%%[![:space:]]*}"}
    if [[ "$line" != /* && "$line" != [A-Za-z]:[/\\]* ]]; then
      line="$2/$line"
    fi
  fi
  printf -v "$1" '%s' "$line"
}

declare -A DELETED=()
DELETED_BUILT=0
IFS= read -r -d '' SPV_CACHE_LOOKUP <<'EOF' || true

FNR == NR { want[$0] = 1; next }
FNR == 1 && $0 "" != sha "" { bad = 1; exit }
FNR == 2 && $0 != "ok" { bad = 1; exit }
FNR <= 2 { next }
after_end { bad = 1; exit }
/^end [0-9]/ { after_end = 1; last = $0; next }
$0 in want { hit[++h] = $0 }
END {
  if (bad || !after_end || last != ("end " (FNR - 3))) exit 1
  for (i = 1; i <= h; i++) print hit[i]
}
EOF
SPV_CACHE_LOOKUP=${SPV_CACHE_LOOKUP%$'\n'}
SHALLOW=0
WALK_FAILED=0

build_deleted_set() {
  ((DELETED_BUILT)) && return 0
  DELETED_BUILT=1

  local head_sha="" git_dir="" common="" cache="" p cands hits
  local -a cached_lines=()
  { head_sha=$(hook::git_untrusted -C "$REPO_ROOT" rev-parse --verify -q HEAD); } 2>/dev/null || return 0
  head_sha=${head_sha//$'\r'/}
  [[ -n "$head_sha" ]] || return 0

  if spv_git_dir_to git_dir && spv_git_common_to common "$git_dir"; then
    cache="$common/guardrails-deleted-paths"
    if [[ -e "$common/shallow" ]]; then
      SHALLOW=1
      return 0
    fi
    if [[ -f "$cache" ]]; then
      printf -v cands '%s\n' "$@"
      if hits=$(LC_ALL=C awk -v sha="$head_sha" "$SPV_CACHE_LOOKUP" - "$cache" <<<"${cands%$'\n'}" 2>/dev/null); then
        if [[ -n "$hits" ]]; then
          mapfile -t cached_lines <<<"$hits"
          for p in "${cached_lines[@]}"; do
            DELETED["$p"]=1
          done
        fi
        return 0
      fi
    fi
  elif [[ "$(git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
    SHALLOW=1
    return 0
  fi

  local walk walk_status=0
  walk=$(hook::git_untrusted -C "$REPO_ROOT" -c core.quotePath=false log HEAD -m --no-renames --diff-filter=D --name-only --pretty=format: 2>/dev/null) ||
    walk_status=$?
  if ((walk_status != 0)); then
    WALK_FAILED=1
    return 0
  fi

  local -a walk_lines=()
  mapfile -t walk_lines <<<"${walk//$'\r'/}"
  for p in "${walk_lines[@]}"; do
    [[ -n "$p" ]] && DELETED["$p"]=1
  done

  if [[ -n "$cache" ]]; then
    local body=$head_sha$'\n'ok$'\n'
    if ((${#DELETED[@]} > 0)); then
      for p in "${!DELETED[@]}"; do
        body+=$p$'\n'
      done
    fi
    printf '%send %d\n' "$body" "${#DELETED[@]}" 2>/dev/null >"$cache" || :
  fi
}

moved_hint() {
  local -a matches=()
  tracked_basename_matches "${1##*/}" || return 1
  ((${#matches[@]} == 1)) && printf '%s' "${matches[0]}"
}

declare -A CHECKED=()
ABSENT_CANDS=()
MISSING=()
ABSENT=0

spv_tokens
RAW_TOKENS=(${SPV_OUT[@]+"${SPV_OUT[@]}"})
if [[ "$TOOL" == "Edit" ]]; then
  reconstruct_partial_edit
  if ((${#RECON_OUT[@]})); then
    RAW_TOKENS+=("${RECON_OUT[@]}")
  fi
fi
((${#RAW_TOKENS[@]})) && ensure_tracked_files

for raw in "${RAW_TOKENS[@]}"; do
  [[ -n "$raw" ]] || continue
  normalize_candidate "$raw"
  cand=$NORM_CAND
  [[ -n "$cand" ]] || continue

  [[ -n "${CHECKED[$cand]:-}" ]] && continue
  CHECKED["$cand"]=1

  [[ -e "$REPO_ROOT/${cand%/}" || -L "$REPO_ROOT/${cand%/}" ]] && continue
  ABSENT=1
  ABSENT_CANDS+=("$cand")
done

((${#ABSENT_CANDS[@]})) && build_deleted_set "${ABSENT_CANDS[@]}"

for cand in ${ABSENT_CANDS[@]+"${ABSENT_CANDS[@]}"}; do
  [[ -n "${DELETED[$cand]:-}" ]] || continue

  ls_line=$(hook::git_untrusted -C "$REPO_ROOT" ls-files -v -- ":(literal)${cand%/}" 2>/dev/null) || ls_line=""
  ls_line=${ls_line//$'\r'/}
  ls_tag=${ls_line:0:1}
  [[ "$ls_tag" == [Ss] ]] && continue

  MISSING+=("$cand")
done

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local findings_json="[]" file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "$REPO_ROOT"
  if ((${#MISSING[@]} > 0)); then
    findings_json=$(printf '%s\n' "${MISSING[@]}" | jq -Rn '[inputs]' 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "stale-path-verify" "PostToolUse" "${1:-ok}" "$start" "$data" "$REPO_ROOT"
}

if ((SHALLOW)) && ((ABSENT)); then
  if hook::notice_once "guardrails-stale-path-verify-shallow" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "" \
      "stale-path-verify is off: this clone is shallow. \`git fetch --unshallow\` turns it on."
  fi
  emit_tel skipped
  exit 0
fi

if ((WALK_FAILED)) && ((ABSENT)); then
  if hook::notice_once "guardrails-stale-path-verify-walk-failed" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "" \
      "stale-path-verify is off: \`git log --diff-filter=D\` failed here (a partial clone offline or a damaged object store are the usual causes)."
  fi
  emit_tel skipped
  exit 0
fi

if ((${#MISSING[@]} > 0)); then
  show_file="$FILE"
  [[ "$FILE" == "${REPO_ROOT%/}/"?* ]] && show_file="${FILE#"${REPO_ROOT%/}/"}"
  lines=""
  for m in "${MISSING[@]}"; do
    hint=$(moved_hint "$m")
    if [[ -n "$hint" ]]; then
      lines+="$m (now at: $hint)"$'\n'
    else
      lines+="$m"$'\n'
    fi
  done
  spv_ctx=""
  hook::findings_to spv_ctx \
    "stale-path-verify: cited path(s) in $show_file were deleted from this repo:" \
    "$lines" --max 10
  hook::ctx_append "$spv_ctx"
  hook::ctx_append "A path cited as a deletion record is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
