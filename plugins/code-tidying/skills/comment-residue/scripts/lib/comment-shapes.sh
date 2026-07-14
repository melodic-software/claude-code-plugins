# shellcheck shell=bash
# Shared comment-residue detectors for /comment-residue (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Residue shapes and treatments".
#
# Residue = comment text that only makes sense outside the code's present state: history
# narration, plan/session references, conversational antecedents, ticket/PR back-references.
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
  [[ "$prev" == *'comment-residue-ignore'* ]] && return 0
  [[ "$line" == *'comment-residue-ignore'* ]] && return 0
  return 1
}

# Extract the comment portion of a line, or empty if the line carries no recognized comment
# leader. Approximate by design — a leader inside a string literal may yield a false comment,
# but the residue-keyword gate below makes that harmless (code words never match).
cr_comment_text() {
  local line="${1//$'\r'/}"
  [[ "$line" =~ ^[[:space:]]*#! ]] && return 0 # shebang, not a comment
  local rest=""
  if [[ "$line" == *"//"* ]]; then
    rest="${line#*//}"
  elif [[ "$line" == *"/*"* ]]; then
    rest="${line#*/\*}"
    rest="${rest%%\*/*}"
  elif [[ "$line" =~ ^[[:space:]]*\*[[:space:]] ]]; then
    rest="${line#*\*}"
  elif [[ "$line" == *"#"* ]]; then
    rest="${line#*#}"
  elif [[ "$line" == *"--"* ]]; then
    rest="${line#*--}"
  fi
  printf '%s' "$rest"
}

# TODO(#issue) and its kin are the sanctioned back-reference — never flag their ticket ref.
cr_is_sanctioned_todo() {
  [[ "$1" =~ (TODO|FIXME|HACK|XXX)([[:space:]]*\(#?[A-Za-z0-9_-]+\))? ]]
}

# Emit zero or more shape names (one per line on stdout). Return 1 if any emitted (cosmetic;
# the caller reads stdout).
cr_detect_shapes() {
  local line="$1"
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

  # ticket-pr-residue (tier 2): back-reference to a tracker/PR/branch a future reader won't see.
  # Sanctioned TODO(#issue) is exempt.
  if ! cr_is_sanctioned_todo "$ct"; then
    if [[ "$lc" =~ (pull[[:space:]]request|see[[:space:]](pr|mr|issue)|pr[[:space:]]#?[0-9]|from[[:space:]]branch|in[[:space:]]this[[:space:]]session) ]] ||
      [[ "$lc" =~ (ticket|issue|jira|linear)[[:space:]]#?[a-z0-9]*-?[0-9] ]]; then
      printf '%s\n' 'ticket-pr-residue'
      found=1
    fi
  fi

  return "$found"
}

cr_shape_tier() {
  case "$1" in
  history-narration | plan-reference | conversational-antecedent) printf '1' ;;
  ticket-pr-residue) printf '2' ;;
  *) printf '3' ;;
  esac
}
