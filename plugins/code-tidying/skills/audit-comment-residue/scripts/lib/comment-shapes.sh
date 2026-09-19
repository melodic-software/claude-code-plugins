# shellcheck shell=bash
# Shared comment-residue detectors for /audit-comment-residue (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Residue shapes and treatments".
#
# Residue = comment text that only makes sense outside the code's present state: history
# narration, plan/session references, conversational antecedents, ticket/PR back-references,
# origin notes naming where a block came from or when it was added.
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

# Extract the comment portion of a line, or empty if the line carries no recognized comment
# leader. A leader (`//`, `/*`, `#`, `--`) only opens a comment when it sits OUTSIDE a string
# literal, so a `//` inside a URL or a residue-shaped phrase inside a quoted string is not
# mistaken for a comment. The scan tracks "...", '...', and `...` spans (with `\` escapes) up to
# the first real leader, then returns the remainder verbatim — apostrophes in comment prose
# ("it's", "no longer") are never treated as strings because the leader has already been found.
# Heuristic, not a full per-language lexer: escaped quotes inside single-quoted shell strings and
# other language-specific quoting quirks are approximated, which is sufficient for a read-only audit.
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
      printf '%s' "${line:i+2}"
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
  [[ "$1" =~ (TODO|FIXME|HACK|XXX) ]]
}

# A line whose first non-blank characters are a comment leader. A trailing comment on a code
# line is NOT one, so a license block never runs on through code.
cr_is_comment_line() {
  [[ "$1" =~ ^[[:space:]]*(#|//|/\*|\*|--) ]]
}

# License or attribution cue, tested against comment TEXT. Narrow on purpose: `copyright` and
# `(c)` are ordinary words a comment uses ("to satisfy the copyright audit", "the callback
# signature f(c)"), so each needs corroboration — a year, a (c)/© sign, or the start of the
# comment — before it exempts anything.
cr_has_license_cue() {
  local lc="${1,,}"
  [[ "$lc" =~ (spdx-license-identifier|licensed[[:space:]]+under|license:) ]] && return 0
  [[ "$lc" =~ copyright[[:space:]]*(\(c\)|©|[0-9]{4}) ]] && return 0
  [[ "$lc" =~ ^[[:space:]]*copyright ]] && return 0
  [[ "$lc" =~ \(c\)[[:space:]]*[0-9]{4} ]] && return 0
  return 1
}

# Line numbers belonging to a license block: a run of contiguous comment lines in which at
# least one line carries a license cue. The whole run is exempt from origin-note, because a
# NOTICE header states its licence once and then attributes on a line of its own. The run ends
# at the first non-comment line, so the same sentence elsewhere in the file is unaffected.
cr_license_block_lines() {
  local line n=0 start=0 cue=0 i
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    if cr_is_comment_line "$line"; then
      ((start == 0)) && start=$n
      ((cue)) || { cr_has_license_cue "$(cr_comment_text "$line")" && cue=1; }
      continue
    fi
    ((start > 0 && cue)) && for ((i = start; i < n; i++)); do printf '%s\n' "$i"; done
    start=0
    cue=0
  done <"$1"
  ((start > 0 && cue)) && for ((i = start; i <= n; i++)); do printf '%s\n' "$i"; done
  return 0
}

# Emit zero or more shape names (one per line on stdout). Return 1 if any emitted (cosmetic;
# the caller reads stdout).
cr_detect_shapes() {
  local line="$1"
  local in_license_block="${2:-0}"
  local ct
  ct="$(cr_comment_text "$line")"
  [[ -z "${ct//[[:space:]]/}" ]] && return 0
  local lc="${ct,,}"
  local found=0

  # history-narration (tier 1): the comment narrates what the code used to be.
  if [[ "$lc" =~ (used[[:space:]]to|no[[:space:]]longer|previously|formerly) ]] ||
    [[ "$lc" =~ (changed[[:space:]](from|to)|renamed[[:space:]](from|to)|refactored[[:space:]](from|to|into)) ]] ||
    [[ "$lc" =~ (we[[:space:]](switched|changed|pivoted|migrated)|this[[:space:]](used[[:space:]]to|was[[:space:]](previously|formerly))) ]] ||
    [[ "$lc" =~ now[[:space:]](does|returns|handles|uses|it[[:space:]]) ]]; then
    printf '%s\n' 'history-narration'
    found=1
  fi

  # plan-reference (tier 1): references a work plan / session / changeset, not the code.
  if [[ "$lc" =~ (per[[:space:]]the[[:space:]]plan|as[[:space:]]planned|replaces[[:space:]]the[[:space:]]old) ]] ||
    [[ "$lc" =~ in[[:space:]]this[[:space:]](pr|change|refactor|commit|session) ]] ||
    [[ "$lc" =~ (task|plan|phase|step)[[:space:]]#?[0-9]+[[:space:]]+(of|in)[[:space:]]the[[:space:]]plan ]]; then
    printf '%s\n' 'plan-reference'
    found=1
  fi

  # conversational-antecedent (tier 1): addresses the requester / the producing conversation.
  if [[ "$lc" =~ (per[[:space:]]your[[:space:]]request|as[[:space:]]requested|per[[:space:]]our[[:space:]](conversation|discussion|chat)) ]] ||
    [[ "$lc" =~ as[[:space:]](you|we)[[:space:]](asked|requested|discussed|mentioned|said|wanted|decided) ]] ||
    [[ "$lc" =~ (you[[:space:]](asked|wanted|mentioned|requested)|like[[:space:]]you[[:space:]]said) ]]; then
    printf '%s\n' 'conversational-antecedent'
    found=1
  fi

  # origin-note (tier 1): the comment names where the block came from or when it was
  # added. Git history owns both. The cue must open the comment or a clause inside it
  # and must be a whole word, so an ordinary description ("bytes copied from the source
  # buffer", "helpers exported from index.ts") is not a finding. An origin VERB is
  # required, so a bare date matches nothing, and the stamp verbs provenance:audit keys
  # on (verified, checked, confirmed, as of) are deliberately absent.
  #
  # Tier 1 reads "remove", so two comment classes are exempt whatever verb they open
  # with: a marker comment, which is tracked work rather than residue, and a license or
  # attribution header, whose text the reader may be legally required to keep. The
  # marker test reuses cr_is_sanctioned_todo rather than redefining which markers count.
  # The license test is BLOCK-scoped and the caller owns it, because a NOTICE header
  # states its licence once and attributes on a separate line; cr_license_block_lines
  # computes the run and the caller passes the verdict in.
  if ! cr_is_sanctioned_todo "$ct" && ((!in_license_block)); then
    if [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+|\([[:space:]]*)(ported|copied|migrated|adapted|borrowed|lifted|taken)[[:space:]]+from ]] ||
      [[ "$lc" =~ (^[[:space:]]*|[,\;:][[:space:]]+)(added|merged|introduced|backported|ported)[[:space:]]+(on[[:space:]]+)?[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
      printf '%s\n' 'origin-note'
      found=1
    fi
  fi

  # ticket-pr-residue (tier 2): back-reference to a tracker/PR/branch a future reader won't see.
  # Sanctioned TODO(#issue) is exempt.
  if ! cr_is_sanctioned_todo "$ct"; then
    if [[ "$lc" =~ (pull[[:space:]]request|see[[:space:]](pr|mr|issue)|pr[[:space:]]#?[0-9]|from[[:space:]]branch|in[[:space:]]this[[:space:]]session) ]] ||
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
  ticket-pr-residue) printf '2' ;;
  *) printf '3' ;;
  esac
}
