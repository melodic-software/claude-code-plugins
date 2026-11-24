# shellcheck shell=bash

cr_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  printf '%s' "$line"
}

cr_is_code_file() {
  case "${1,,}" in
  *.cs | *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.py | *.sh | *.bash | *.ps1 | *.psm1 | \
    *.go | *.rs | *.java | *.kt | *.rb | *.lua | *.sql | *.c | *.h | *.cpp | *.hpp | *.cc | \
    *.yaml | *.yml | *.toml) return 0 ;;
  *) return 1 ;;
  esac
}

cr_line_skipped() {
  local prev="$1" line="$2"
  [[ "$prev" == *'comment-residue-ignore'* || "$line" == *'comment-residue-ignore'* ]]
}

cr_comment_text() {
  REPLY=""
  local line="${1//$'\r'/}"
  [[ "$line" =~ ^[[:space:]]*#! ]] && return 0
  if [[ "$line" =~ ^[[:space:]]*\*[[:space:]] ]]; then
    REPLY="${line#*\*}"
    return 0
  fi
  local n=${#line} i ch nx quote="" rest
  for ((i = 0; i < n; i++)); do
    ch="${line:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$ch" == "\\" ]]; then
        ((i++))
        continue
      fi
      [[ "$ch" == "$quote" ]] && quote=""
      continue
    fi
    case "$ch" in
    '"' | \' | '`')
      quote="$ch"
      continue
      ;;
    *) ;;
    esac
    nx="${line:i+1:1}"
    if [[ "$ch$nx" == '//' || "$ch$nx" == '--' ]]; then
      rest="${line:i+2}"
      [[ "$ch$nx" == '//' ]] && rest="${rest#[/!]}"
      REPLY="$rest"
      return 0
    elif [[ "$ch$nx" == '/*' ]]; then
      rest="${line:i+2}"
      REPLY="${rest%%\*/*}"
      return 0
    elif [[ "$ch" == '#' ]]; then
      REPLY="${line:i+1}"
      return 0
    fi
  done
  return 0
}

cr_is_sanctioned_todo() {
  local re='(^[[:space:]]*|[,;:.][[:space:]]+|\([[:space:]]*)(TODO|FIXME|HACK|XXX)[(:]'
  [[ "$1" =~ $re ]]
}

cr_is_comment_line() {
  [[ "$1" =~ ^[[:space:]]*(#|//|/\*|\*|--) ]]
}

cr_has_license_cue() {
  local lc="${1,,}"
  [[ "$lc" =~ (spdx-license-identifier|licensed[[:space:]]+under|license:) ]] && return 0
  [[ "$lc" =~ copyright[[:space:]]*(\(c\)|©|[0-9]{4}) ]] && return 0
  [[ "$lc" =~ ^[[:space:]]*copyright ]] && return 0
  [[ "$lc" =~ \(c\)[[:space:]]*[0-9]{4} ]] && return 0
  return 1
}

cr_has_workaround_cue() {
  local lc="${1,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_])(work[-[:space:]]?arounds?|works[[:space:]]+around|working[[:space:]]+around|worked[[:space:]]+around)([^[:alnum:]_]|$) ]]
}

cr_has_workaround_justification() {
  local lc="${1,,}"
  local sb='(^|[^[:alnum:]])' eb='([^[:alnum:]]|$)'
  local ev='(ships?|shipped|lands?|landed|releases?|released|merges?|merged|fix(es|ed)?|resolved|available|supports?|upgrades?|upgraded)'
  [[ "$lc" =~ https?:// || "$lc" =~ \#[0-9]+ || "$lc" =~ ${sb}rfc[[:space:]-]?[0-9]+ ]] && return 0
  [[ "$lc" =~ ${sb}until([[:space:]]+[[:alpha:]]+){0,2}[[:space:]]+v?[0-9] ]] && return 0
  [[ "$lc" =~ ${sb}until[^[:alnum:]](.*[^[:alnum:]])?${ev}${eb} ]] && return 0
  [[ "$lc" =~ ${sb}(remove|drop|delete|revert)([[:space:]]+[[:alnum:]]+)?[[:space:]]+(when|once|after)${eb} ]] && return 0
  [[ "$lc" =~ ${sb}once${eb}.*${sb}(ships|lands|releases|merges|is[[:space:]]+(fixed|released|merged|resolved|available))${eb} ]] && return 0
  return 1
}

cr_run_lines_with() {
  local predicate="$1" line n=0 start=0 cue=0 i
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if cr_is_comment_line "$line"; then
      ((start == 0)) && start=$n
      ((cue)) || {
        cr_comment_text "$line"
        "$predicate" "$REPLY" && cue=1
      }
      continue
    fi
    ((start > 0 && cue)) && for ((i = start; i < n; i++)); do printf '%s\n' "$i"; done
    start=0
    cue=0
  done <"$2"
  ((start > 0 && cue)) && for ((i = start; i <= n; i++)); do printf '%s\n' "$i"; done
  return 0
}

cr_license_block_lines() {
  cr_run_lines_with cr_has_license_cue "$1"
}

cr_justified_run_lines() {
  cr_run_lines_with cr_has_workaround_justification "$1"
}

cr_detect_shapes() {
  cr_comment_text "$1"
  cr_detect_shapes_text "$REPLY" "${2:-0}" "${3:-0}"
}

cr_add_shape() {
  REPLY+="${REPLY:+$'\n'}$1"
}

cr_detect_shapes_text() {
  local ct="$1" in_license_block="${2:-0}" in_justified_run="${3:-0}"
  REPLY=""
  [[ -z "${ct//[[:space:]]/}" ]] && return 0
  local lc="${ct,,}"

  local sb='(^|[^[:alnum:]])' eb='([^[:alnum:]]|$)'

  if [[ "$lc" =~ ${sb}(used[[:space:]]to|no[[:space:]]longer|previously|formerly)${eb} ]] ||
    [[ "$lc" =~ ${sb}(changed[[:space:]](from|to)|renamed[[:space:]](from|to)|refactored[[:space:]](from|to|into))${eb} ]] ||
    [[ "$lc" =~ ${sb}(we[[:space:]](switched|changed|pivoted|migrated)|this[[:space:]](used[[:space:]]to|was[[:space:]](previously|formerly)))${eb} ]] ||
    [[ "$lc" =~ ${sb}now[[:space:]]((does|returns|handles|uses)${eb}|it[[:space:]]) ]]; then
    cr_add_shape 'history-narration'
  fi

  if [[ "$lc" =~ ${sb}(per[[:space:]]the[[:space:]]plan|as[[:space:]]planned|replaces[[:space:]]the[[:space:]]old)${eb} ]] ||
    [[ "$lc" =~ ${sb}in[[:space:]]this[[:space:]](pr|change|refactor|commit|session)${eb} ]] ||
    [[ "$lc" =~ ${sb}(task|plan|phase|step)[[:space:]]#?[0-9]+[[:space:]]+(of|in)[[:space:]]the[[:space:]]plan${eb} ]]; then
    cr_add_shape 'plan-reference'
  fi

  if [[ "$lc" =~ ${sb}(per[[:space:]]your[[:space:]]request|as[[:space:]]requested|per[[:space:]]our[[:space:]](conversation|discussion|chat))${eb} ]] ||
    [[ "$lc" =~ ${sb}as[[:space:]](you|we)[[:space:]](asked|requested|discussed|mentioned|said|wanted|decided)${eb} ]] ||
    [[ "$lc" =~ ${sb}(you[[:space:]](asked|wanted|mentioned|requested)|like[[:space:]]you[[:space:]]said)${eb} ]]; then
    cr_add_shape 'conversational-antecedent'
  fi

  if ! cr_is_sanctioned_todo "$ct" && ((!in_license_block)); then
    if [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+|\([[:space:]]*)(ported|copied|migrated|adapted|borrowed|lifted|taken)[[:space:]]+from${eb} ]] ||
      [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+)(added|merged|introduced|backported|ported)[[:space:]]+(on[[:space:]]+)?[0-9]{4}-[0-9]{2}-[0-9]{2}(t[0-9:]{4,8}z?)?${eb} ]]; then
      cr_add_shape 'origin-note'
    fi
  fi

  local wk="$lc" rre='replaces[[:space:]]+the[[:space:]]+old'
  while [[ "$wk" =~ $rre ]]; do wk="${wk/"${BASH_REMATCH[0]}"/ }"; done
  if [[ "$wk" =~ ${sb}(as[[:space:]]+before|always[[:space:]]+used)${eb} ]] ||
    [[ "$wk" =~ ${sb}the[[:space:]]+old[[:space:]]+[[:alnum:]] ]] ||
    [[ "$wk" =~ ${sb}phase[[:space:]]+[0-9]+([a-z]${eb}|[[:space:]]*([^[:alnum:][:space:]]|$)) ]]; then
    cr_add_shape 'history-narration-weak'
  fi

  local workaround=0
  if cr_has_workaround_cue "$ct"; then
    workaround=1
    if ((!in_justified_run)) && ! cr_has_workaround_justification "$ct"; then
      cr_add_shape 'unjustified-workaround'
    fi
  fi

  if ((!workaround)) && ! cr_is_sanctioned_todo "$ct"; then
    if [[ "$lc" =~ (see[[:space:]]+(pr|mr|issue)|(^|[^[:alnum:]])(pr|issue|mr)[[:space:]]*#?[0-9]|github\.com/[^[:space:]]+/(pull|issues)/[0-9]+|[a-z0-9_.-]+/[a-z0-9_.-]+#[0-9]+|(^|[^[:alnum:]_.-])[a-z0-9][a-z0-9_.-]{2,}#[0-9]+([^[:alnum:]]|$)|from[[:space:]]+branch|from[[:space:]]+(the[[:space:]]+)?[a-z0-9][a-z0-9._/-]*[[:space:]]+branch|in[[:space:]]this[[:space:]]session([^[:alnum:]]|$)) ]] ||
      [[ "$lc" =~ (ticket|issue|jira|linear)([[:space:]]#?[a-z0-9]*-?[0-9]|-[0-9]) ]]; then
      cr_add_shape 'ticket-pr-residue'
    fi
  fi

  return 0
}

cr_shape_tier() {
  case "$1" in
  history-narration | plan-reference | conversational-antecedent | origin-note) printf '1' ;;
  history-narration-weak | ticket-pr-residue | unjustified-workaround) printf '2' ;;
  *) printf '3' ;;
  esac
}
