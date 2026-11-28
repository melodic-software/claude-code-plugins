# shellcheck shell=bash

[[ -n "${_PR_LINKAGE_VALIDATOR_LOADED:-}" ]] && return 0
readonly _PR_LINKAGE_VALIDATOR_LOADED=1

UNICODE_SPACES=(
  $'\xc2\xa0' $'\xe1\x9a\x80'
  $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83'
  $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87'
  $'\xe2\x80\x88' $'\xe2\x80\x89' $'\xe2\x80\x8a'
  $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\xe2\x80\xaf'
  $'\xe2\x81\x9f' $'\xe3\x80\x80' $'\xef\xbb\xbf'
)

linkage::chomp_to() {
  local __plv_dest="$1" __plv_s="$2"
  if [[ "$__plv_s" =~ $_PLV_CHOMP_TAIL_ERE ]]; then
    __plv_s="${__plv_s:0:${#__plv_s}-${#BASH_REMATCH[0]}+1}"
  elif [[ "$__plv_s" =~ $_PLV_ALL_NEWLINES_ERE ]]; then
    __plv_s=""
  fi
  printf -v "$__plv_dest" '%s' "$__plv_s"
}
_PLV_CHOMP_TAIL_ERE=$'[^\n]\n+$'
_PLV_ALL_NEWLINES_ERE=$'^\n+$'

umask 077
_PR_LINKAGE_HERESTRING_MAX=16000

linkage::split_lines() {
  if ((${#1} < _PR_LINKAGE_HERESTRING_MAX)); then
    readarray -t LINKAGE_LINES <<<"$1"
    return 0
  fi
  local __plv_file="${TMPDIR:-/tmp}/pr-linkage-lines.$$"
  printf '%s\n' "$1" >"$__plv_file"
  readarray -t LINKAGE_LINES <"$__plv_file"
  rm -f "$__plv_file"
}

strip_html_comments_to() {
  local __plv_dest="$1" body="$2" line rest kept out="" in_comment=0 sp i=0
  for sp in "${UNICODE_SPACES[@]}"; do body="${body//"$sp"/ }"; done
  linkage::split_lines "$body"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    line="${LINKAGE_LINES[i]}"
    rest="${line%$'\r'}"
    kept=""
    while [[ -n "$rest" ]]; do
      if ((in_comment)); then
        if [[ "$rest" == *"-->"* ]]; then
          rest="${rest#*-->}"
          in_comment=0
        else
          rest=""
        fi
      else
        if [[ "$rest" == *"<!--"* ]]; then
          kept+="${rest%%<!--*}"
          rest="${rest#*<!--}"
          in_comment=1
        else
          kept+="$rest"
          rest=""
        fi
      fi
    done
    out+="$kept"$'\n'
  done
  linkage::chomp_to "$__plv_dest" "$out"
}

trim_to() {
  local __plv_dest="$1" s="$2"
  [[ "$s" =~ ^[[:space:]]+ ]] && s="${s:${#BASH_REMATCH[0]}}"
  [[ "$s" =~ [^[:space:]][[:space:]]+$ ]] && s="${s:0:${#s}-${#BASH_REMATCH[0]}+1}"
  printf -v "$__plv_dest" '%s' "$s"
}

CLOSING_ERE='(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:blank:]]*:?[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'
NON_CLOSING_ERE='^ {0,3}(refs|relates[[:blank:]]+to):[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[[:blank:]]*$'
NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'
# The second keyword word is `to`: POSIX leftmost-longest matching reads `Closes ENG-123` as `Closes EN`:
# https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap09.html
TRACKER_LINK_ERE='^ {0,3}([A-Za-z]+([[:blank:]]+[Tt][Oo])?)([[:blank:]]*:[[:blank:]]*|[[:blank:]]+)([A-Z][A-Z0-9_]*-[0-9]+|(local-markdown|github|gitea|jira|linear):[^[:space:]#/][^[:space:]#]*#[0-9]+)[[:blank:]]*$'
TRACKER_KEYWORD_ERE='^(close[sd]?|fix(es|ed)?|resolve[sd]?|refs|relates[[:blank:]]+to)$'
_PLV_WORD_ERE="[A-Za-z][A-Za-z']*"
_PLV_DELIM_TAIL_ERE='[.!?;,][^.!?;,]*$'

negation_trigger_to() {
  local __plv_dest="$1" tail="$2" lower n i tok IFS=' '
  local -a toks=() words=()
  printf -v "$__plv_dest" '%s' ""
  [[ "$tail" =~ $_PLV_DELIM_TAIL_ERE ]] && tail="${tail:${#tail}-${#BASH_REMATCH[0]}+1}"
  tail="${tail//$'\xe2\x80\x99'/\'}"
  tail="${tail//[!A-Za-z\']/ }"
  # shellcheck disable=SC2206  # split on blanks is the point; the text holds no glob characters
  toks=($tail)
  for ((i = ${#toks[@]} - 1; i >= 0 && ${#words[@]} < 5; i--)); do
    tok="${toks[i]}"
    [[ "$tok" =~ $_PLV_WORD_ERE ]] && words=("${BASH_REMATCH[0]}" ${words[@]+"${words[@]}"})
  done
  n=${#words[@]}
  for ((i = 0; i < n; i++)); do
    lower="${words[i],,}"
    [[ "$lower" == not ]] && ((i + 1 < n)) && [[ "${words[i + 1],,}" == only ]] && continue
    case "$lower" in
    not | never | no | without | deliberately | intentionally | *"n't")
      printf -v "$__plv_dest" '%s' "${words[i]}"
      return 0
      ;;
    *) ;;
    esac
  done
}

LINKAGE_NEGATED=()
scan_linkage() {
  local line lower chunk m pre start len off before after text _plv_trigger i found=1
  local -A negated_seen=()
  LINKAGE_NEGATED=()
  linkage::split_lines "$1"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    line="${LINKAGE_LINES[i]}"
    lower="${line,,}"
    [[ "$lower" =~ $NON_CLOSING_ERE ]] && found=0
    [[ "$line" =~ $TRACKER_LINK_ERE && "${BASH_REMATCH[1],,}" =~ $TRACKER_KEYWORD_ERE ]] && found=0
    off=0
    while chunk="${lower:off}" && [[ "$chunk" =~ $CLOSING_ERE ]]; do
      m="${BASH_REMATCH[0]}"
      pre="${chunk%%"$m"*}"
      start=$((off + ${#pre}))
      len=${#m}
      off=$((start + len))
      before=""
      ((start > 0)) && before="${lower:start-1:1}"
      after="${lower:off:1}"
      [[ "$before" == [a-z0-9_] || "$after" == [a-z0-9_] ]] && continue
      text="${line:start:len}"
      negation_trigger_to _plv_trigger "${line:0:start}"
      if [[ -z "$_plv_trigger" ]]; then
        found=0
        continue
      fi
      [[ -n "${negated_seen[$text]:-}" ]] && continue
      negated_seen[$text]=1
      LINKAGE_NEGATED+=("\"${text}\" (trigger \"${_plv_trigger}\")")
    done
  done
  ((found == 0)) && return 0
  lower=$'\n'"${1,,}"$'\n'
  [[ "$lower" =~ $NO_ISSUE_ERE ]]
}

section_content_to() {
  local __plv_dest="$1" body="$2" heading_lc="${3,,}" t start=0 lvl i=0 out=""
  printf -v "$__plv_dest" '%s' ""
  linkage::split_lines "$body"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    trim_to t "${LINKAGE_LINES[i]}"
    [[ "${t,,}" =~ ^##[[:space:]]+"${heading_lc}"$ ]] && {
      start=$((i + 1))
      break
    }
  done
  ((start)) || return 1
  for ((i = start; i < ${#LINKAGE_LINES[@]}; i++)); do
    trim_to t "${LINKAGE_LINES[i]}"
    if [[ "$t" =~ ^#+[[:space:]]+[^[:space:]] ]]; then
      lvl=0
      while [[ "${t:lvl:1}" == "#" ]]; do ((lvl++)); done
      ((lvl <= 2)) && break
    fi
    out+="${LINKAGE_LINES[i]}"$'\n'
  done
  trim_to "$__plv_dest" "$out"
}

mask_markdown_code_to() {
  local __plv_dest="$1" body="$2" line rest rendered fence_char="" fence_len=0 in_fence=0
  local marker_run marker_rest f nf ticks j r nruns ticks_text out="" li=0 IFS
  local -a fields runs_before runs_len closer last
  local had_noglob=0
  [[ $- == *f* ]] && had_noglob=1
  set -f
  local fence_re='^ {0,3}(`{3,}|~{3,})(.*)$'
  linkage::split_lines "$body"
  for ((li = 0; li < ${#LINKAGE_LINES[@]}; li++)); do
    line="${LINKAGE_LINES[li]}"
    rest="${line%$'\r'}"
    if ((in_fence)); then
      if [[ "$rest" =~ $fence_re ]]; then
        marker_run="${BASH_REMATCH[1]}"
        marker_rest="${BASH_REMATCH[2]}"
        if [[ "${marker_run:0:1}" == "$fence_char" && ${#marker_run} -ge $fence_len && "$marker_rest" =~ ^[[:space:]]*$ ]]; then
          in_fence=0
          fence_char=""
          fence_len=0
        fi
      fi
      out+=$'\n'
      continue
    fi
    if [[ "$rest" =~ $fence_re ]]; then
      marker_run="${BASH_REMATCH[1]}"
      marker_rest="${BASH_REMATCH[2]}"
      if [[ "${marker_run:0:1}" != '`' || "$marker_rest" != *'`'* ]]; then
        in_fence=1
        fence_char="${marker_run:0:1}"
        fence_len=${#marker_run}
        out+=$'\n'
        continue
      fi
    fi
    if [[ "$rest" == "    "* || "$rest" == $'\t'* ]]; then
      out+=$'\n'
      continue
    fi
    if [[ "$rest" != *'`'* ]]; then
      out+="$rest"$'\n'
      continue
    fi
    IFS='`'
    # shellcheck disable=SC2206  # the split is the point; set -f above stops globbing
    fields=($rest)
    [[ "$rest" == *'`' ]] && fields+=("")
    nf=${#fields[@]}
    runs_before=()
    runs_len=()
    for ((f = 1; f < nf; f++)); do
      runs_before+=("$((f - 1))")
      ticks=1
      while ((f < nf - 1)) && [[ -z "${fields[f]}" ]]; do
        ticks=$((ticks + 1))
        f=$((f + 1))
      done
      runs_len+=("$ticks")
    done
    nruns=${#runs_len[@]}
    closer=()
    last=()
    for ((r = nruns - 1; r >= 0; r--)); do
      ticks=${runs_len[r]}
      closer[r]=${last[ticks]:--1}
      last[ticks]=$r
    done
    rendered="${fields[0]}"
    for ((r = 0; r < nruns; r++)); do
      j=${closer[r]}
      if ((j >= 0)); then
        r=$j
      else
        printf -v ticks_text '%*s' "${runs_len[r]}" ''
        rendered+="${ticks_text// /\`}"
      fi
      rendered+="${fields[runs_before[r] + runs_len[r]]}"
    done
    out+="$rendered"$'\n'
  done
  ((had_noglob)) || set +f
  linkage::chomp_to "$__plv_dest" "$out"
}

linkage::section_problems() {
  local _plv_content="" _plv_masked="$1" heading
  shift
  for heading in "$@"; do
    # shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
    if section_content_to _plv_content "$_plv_masked" "$heading"; then
      [[ -n "$_plv_content" ]] || LINKAGE_PROBLEMS+=("The \"## ${heading}\" section is empty.")
    else
      LINKAGE_PROBLEMS+=("Missing a \"## ${heading}\" section.")
    fi
  done
}

REQUIRED_SECTIONS=(Summary Fix Verification Related)

LINKAGE_BODY=""
LINKAGE_PROBLEMS=()
linkage::scan_body() {
  local _plv_stripped="" _plv_negated="" _plv_linked=0
  strip_html_comments_to _plv_stripped "$1"
  mask_markdown_code_to LINKAGE_BODY "$_plv_stripped"
  LINKAGE_PROBLEMS=()
  # shellcheck disable=SC2310  # the exit IS the verdict: linkage present or not
  scan_linkage "$LINKAGE_BODY" || _plv_linked=1
  ((${#LINKAGE_NEGATED[@]} == 0)) || {
    printf -v _plv_negated '%s, ' "${LINKAGE_NEGATED[@]}"
    LINKAGE_PROBLEMS+=("Negated closing reference (${_plv_negated%, }): GitHub still auto-closes the issue on merge. Use \"Refs: #N\" on its own line instead.")
  }
  return "$_plv_linked"
}

linkage::problems() {
  local _plv_linked=0
  # shellcheck disable=SC2310  # the exit IS the verdict: linkage present or not
  linkage::scan_body "$1" || _plv_linked=1
  linkage::section_problems "$LINKAGE_BODY" "${REQUIRED_SECTIONS[@]}"
  ((_plv_linked == 0)) ||
    LINKAGE_PROBLEMS+=('No closing line: add Closes #N, Refs: #N (link without closing), or No linked issue.')
  ((${#LINKAGE_PROBLEMS[@]} == 0))
}

linkage::blocking_problems() {
  # shellcheck disable=SC2310  # only LINKAGE_NEGATED decides; missing linkage is advisory
  linkage::scan_body "$1" || :
  ((${#LINKAGE_PROBLEMS[@]} == 0))
}

linkage::block_message() {
  local p
  echo "BLOCKED: PR body fails the repository's PR-body contract step in $1." >&2
  for p in "${LINKAGE_PROBLEMS[@]}"; do echo "  - $p" >&2; done
  echo "Only a negated closer blocks; a missing closing line or ## Summary, ## Fix, ## Verification or ## Related section is advisory." >&2
}
