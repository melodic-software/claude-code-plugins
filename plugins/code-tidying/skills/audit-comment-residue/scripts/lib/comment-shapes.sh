# shellcheck shell=bash
# Shared comment-residue detectors for /audit-comment-residue (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Residue shapes and treatments".
#
# Detection runs ONLY on the comment portion of a line, so residue-shaped words sitting in
# code (identifiers, string literals) are not flagged.

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

# Extract the comment portion of a line, or empty. A leader (`//`, `/*`, `#`, `--`) opens a
# comment only OUTSIDE a "...", '...', or `...` span, so a URL's `//` or a quoted phrase is
# not a comment. Heuristic, not a per-language lexer: enough for a read-only audit.
cr_comment_text() {
  local line="${1//$'\r'/}"
  [[ "$line" =~ ^[[:space:]]*#! ]] && return 0 # shebang, not a comment
  # Block-comment continuation line ("* ..." inside a /* */ block): whole body is comment.
  if [[ "$line" =~ ^[[:space:]]*\*[[:space:]] ]]; then
    printf '%s' "${line#*\*}"
    return 0
  fi
  local n=${#line} i ch nx quote="" rest
  for ((i = 0; i < n; i++)); do
    ch="${line:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$ch" == "\\" ]]; then
        ((i++)) # skip the escaped character
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
      # `///` and `//!` are doc-comment leaders. Left in the text they occupy the
      # clause-opening position, so a cue right behind one would never anchor.
      [[ "$ch$nx" == '//' ]] && rest="${rest#[/!]}"
      printf '%s' "$rest"
      return 0
    elif [[ "$ch$nx" == '/*' ]]; then
      rest="${line:i+2}"
      printf '%s' "${rest%%\*/*}"
      return 0
    elif [[ "$ch" == '#' ]]; then
      printf '%s' "${line:i+1}"
      return 0
    fi
  done
  return 0
}

# TODO(#issue) and its kin are the sanctioned back-reference — never flag their ticket ref.
cr_is_sanctioned_todo() {
  local re='(^[[:space:]]*|[,;:.][[:space:]]+|\([[:space:]]*)(TODO|FIXME|HACK|XXX)[(:]'
  [[ "$1" =~ $re ]]
}

# A line whose first non-blank characters are a comment leader. A trailing comment on a code
# line is NOT one, so a license block never runs on through code.
cr_is_comment_line() {
  [[ "$1" =~ ^[[:space:]]*(#|//|/\*|\*|--) ]]
}

# License or attribution cue. `copyright` and `(c)` are ordinary words, so each needs a
# year, a (c)/© sign, or the start of the comment as corroboration.
cr_has_license_cue() {
  local lc="${1,,}"
  [[ "$lc" =~ (spdx-license-identifier|licensed[[:space:]]+under|license:) ]] && return 0
  [[ "$lc" =~ copyright[[:space:]]*(\(c\)|©|[0-9]{4}) ]] && return 0
  [[ "$lc" =~ ^[[:space:]]*copyright ]] && return 0
  [[ "$lc" =~ \(c\)[[:space:]]*[0-9]{4} ]] && return 0
  return 1
}

# The comment names a workaround: the cue words, whole, in the comment text.
cr_has_workaround_cue() {
  local lc="${1,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_])(work[-[:space:]]?arounds?|works[[:space:]]+around|working[[:space:]]+around|worked[[:space:]]+around)([^[:alnum:]_]|$) ]]
}

# A workaround is justified by a link (a URL, an issue or PR number, an RFC) or by a
# removal condition (`until`, `remove when`, `drop it once`, `once ... ships`).
cr_has_workaround_justification() {
  local lc="${1,,}"
  local sb='(^|[^[:alnum:]])' eb='([^[:alnum:]]|$)'
  [[ "$lc" =~ https?:// || "$lc" =~ \#[0-9]+ || "$lc" =~ ${sb}rfc[[:space:]-]?[0-9]+ ]] && return 0
  [[ "$lc" =~ ${sb}until${eb} ]] && return 0
  [[ "$lc" =~ ${sb}(remove|drop|delete|revert)([[:space:]]+[[:alnum:]]+)?[[:space:]]+(when|once|after)${eb} ]] && return 0
  [[ "$lc" =~ ${sb}once${eb}.*${sb}(ships|lands|releases|merges|is[[:space:]]+(fixed|released|merged|resolved|available))${eb} ]] && return 0
  return 1
}

# Print the line numbers of every contiguous comment run in which any line's comment text
# passes the named predicate. A trailing comment on a code line starts no run.
cr_run_lines_with() {
  local predicate="$1" line n=0 start=0 cue=0 i
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if cr_is_comment_line "$line"; then
      ((start == 0)) && start=$n
      ((cue)) || { "$predicate" "$(cr_comment_text "$line")" && cue=1; }
      continue
    fi
    ((start > 0 && cue)) && for ((i = start; i < n; i++)); do printf '%s\n' "$i"; done
    start=0
    cue=0
  done <"$2"
  ((start > 0 && cue)) && for ((i = start; i <= n; i++)); do printf '%s\n' "$i"; done
  return 0
}

# A contiguous comment run with any license cue is exempt from origin-note whole: a NOTICE
# header states its license once and attributes on a separate line.
cr_license_block_lines() {
  cr_run_lines_with cr_has_license_cue "$1"
}

# A workaround comment run is justified whole when any of its lines carries the link or
# removal condition, so a condition wrapped onto the next line still counts.
cr_justified_run_lines() {
  cr_run_lines_with cr_has_workaround_justification "$1"
}

# Emit zero or more shape names, one per line; return 1 if any emitted.
cr_detect_shapes() {
  cr_detect_shapes_text "$(cr_comment_text "$1")" "${2:-0}" "${3:-0}"
}

# The same over comment text already extracted from a line, or joined from two lines.
# $2: the line sits in a license block; $3: the line sits in a justified comment run.
cr_detect_shapes_text() {
  local ct="$1"
  local in_license_block="${2:-0}"
  local in_justified_run="${3:-0}"
  [[ -z "${ct//[[:space:]]/}" ]] && return 0
  local lc="${ct,,}"
  local found=0

  # Every tier-1 cue is a whole phrase: the start boundary keeps `formerly` out of `reformerly`
  # and `changed to` out of `unchanged to`; the end boundary keeps `used to` out of `used tokens`.
  local sb='(^|[^[:alnum:]])' eb='([^[:alnum:]]|$)'

  # history-narration (tier 1): the comment narrates what the code used to be.
  if [[ "$lc" =~ ${sb}(used[[:space:]]to|no[[:space:]]longer|previously|formerly)${eb} ]] ||
    [[ "$lc" =~ ${sb}(changed[[:space:]](from|to)|renamed[[:space:]](from|to)|refactored[[:space:]](from|to|into))${eb} ]] ||
    [[ "$lc" =~ ${sb}(we[[:space:]](switched|changed|pivoted|migrated)|this[[:space:]](used[[:space:]]to|was[[:space:]](previously|formerly)))${eb} ]] ||
    [[ "$lc" =~ ${sb}now[[:space:]]((does|returns|handles|uses)${eb}|it[[:space:]]) ]]; then
    printf '%s\n' 'history-narration'
    found=1
  fi

  # plan-reference (tier 1): references a work plan / session / changeset, not the code.
  if [[ "$lc" =~ ${sb}(per[[:space:]]the[[:space:]]plan|as[[:space:]]planned|replaces[[:space:]]the[[:space:]]old)${eb} ]] ||
    [[ "$lc" =~ ${sb}in[[:space:]]this[[:space:]](pr|change|refactor|commit|session)${eb} ]] ||
    [[ "$lc" =~ ${sb}(task|plan|phase|step)[[:space:]]#?[0-9]+[[:space:]]+(of|in)[[:space:]]the[[:space:]]plan${eb} ]]; then
    printf '%s\n' 'plan-reference'
    found=1
  fi

  # conversational-antecedent (tier 1): addresses the requester / the producing conversation.
  if [[ "$lc" =~ ${sb}(per[[:space:]]your[[:space:]]request|as[[:space:]]requested|per[[:space:]]our[[:space:]](conversation|discussion|chat))${eb} ]] ||
    [[ "$lc" =~ ${sb}as[[:space:]](you|we)[[:space:]](asked|requested|discussed|mentioned|said|wanted|decided)${eb} ]] ||
    [[ "$lc" =~ ${sb}(you[[:space:]](asked|wanted|mentioned|requested)|like[[:space:]]you[[:space:]]said)${eb} ]]; then
    printf '%s\n' 'conversational-antecedent'
    found=1
  fi

  # origin-note (tier 1): the comment names where the block came from or when it was
  # added. The cue must open the comment or a clause, be whole words, and carry an origin
  # VERB, so a description ("bytes copied from the buffer") or a bare date is not a finding;
  # attribution:audit's stamp verbs (verified, checked, confirmed, as of) are absent on purpose.
  # The ISO time is spelled out because `T` is alphanumeric and would fail the end boundary.
  # Markers and license headers are exempt; the caller passes the block-scoped license verdict.
  if ! cr_is_sanctioned_todo "$ct" && ((!in_license_block)); then
    if [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+|\([[:space:]]*)(ported|copied|migrated|adapted|borrowed|lifted|taken)[[:space:]]+from([^[:alnum:]]|$) ]] ||
      [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+)(added|merged|introduced|backported|ported)[[:space:]]+(on[[:space:]]+)?[0-9]{4}-[0-9]{2}-[0-9]{2}(t[0-9:]{4,8}z?)?([^[:alnum:]]|$) ]]; then
      printf '%s\n' 'origin-note'
      found=1
    fi
  fi

  # history-narration-weak (tier 2): cues that usually narrate the past but also open ordinary
  # prose ("as before the loop starts", "the old value is compared"), so a person decides.
  # `replaces the old` is plan-reference's, so it is blanked before the `the old <word>` cue.
  local wk="$lc" rre='replaces[[:space:]]+the[[:space:]]+old'
  while [[ "$wk" =~ $rre ]]; do wk="${wk/"${BASH_REMATCH[0]}"/ }"; done
  if [[ "$wk" =~ ${sb}(as[[:space:]]+before|always[[:space:]]+used)${eb} ]] ||
    [[ "$wk" =~ ${sb}the[[:space:]]+old[[:space:]]+[[:alnum:]] ]] ||
    [[ "$wk" =~ ${sb}phase[[:space:]]+[0-9]+([a-z]${eb}|[[:space:]]*([^[:alnum:][:space:]]|$)) ]]; then
    printf '%s\n' 'history-narration-weak'
    found=1
  fi

  # unjustified-workaround (tier 2): the comment names a workaround and gives neither a link
  # nor a removal condition, so nothing tells a reader when the workaround can go.
  local workaround=0
  if cr_has_workaround_cue "$ct"; then
    workaround=1
    if ((!in_justified_run)) && ! cr_has_workaround_justification "$ct"; then
      printf '%s\n' 'unjustified-workaround'
      found=1
    fi
  fi

  # ticket-pr-residue (tier 2): back-reference to a tracker/PR/branch a future reader won't see.
  # Sanctioned TODO(#issue) is exempt, and so is a workaround comment, whose reference is the
  # justification the class above asks for.
  if ((!workaround)) && ! cr_is_sanctioned_todo "$ct"; then
    if [[ "$lc" =~ (see[[:space:]]+(pr|mr|issue)|(^|[^[:alnum:]])(pr|issue|mr)[[:space:]]*#?[0-9]|github\.com/[^[:space:]]+/(pull|issues)/[0-9]+|[a-z0-9_.-]+/[a-z0-9_.-]+#[0-9]+|(^|[^[:alnum:]_.-])[a-z0-9][a-z0-9_.-]{2,}#[0-9]+([^[:alnum:]]|$)|from[[:space:]]+branch|from[[:space:]]+(the[[:space:]]+)?[a-z0-9][a-z0-9._/-]*[[:space:]]+branch|in[[:space:]]this[[:space:]]session([^[:alnum:]]|$)) ]] ||
      [[ "$lc" =~ (ticket|issue|jira|linear)([[:space:]]#?[a-z0-9]*-?[0-9]|-[0-9]) ]]; then
      printf '%s\n' 'ticket-pr-residue'
      found=1
    fi
  fi

  return "$found"
}

cr_shape_tier() {
  case "$1" in
  history-narration | plan-reference | conversational-antecedent | origin-note) printf '1' ;;
  history-narration-weak | ticket-pr-residue | unjustified-workaround) printf '2' ;;
  *) printf '3' ;;
  esac
}
