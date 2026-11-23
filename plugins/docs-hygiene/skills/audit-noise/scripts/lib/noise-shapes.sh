# shellcheck shell=bash

audit_noise_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  local -n _audit_noise_excerpt_out="$2"
  _audit_noise_excerpt_out="$line"
}

audit_noise_line_has_ghost_ref() {
  local rest="$1" path seg after
  local reserved=' handoffs reviews running-retros overengineering enforceability exports lanes docs-hygiene '
  [[ "$rest" == *'.claude/notes/'* ||
    "$rest" == *'.claude/handoffs/'* ||
    "$rest" == *'.claude/review/'* ]] && return 0
  while [[ "$rest" =~ \.work/([a-z0-9][a-z0-9_-]*)/ ]]; do
    path="${BASH_REMATCH[0]}"
    seg="${BASH_REMATCH[1]}"
    after="${rest#*"$path"}"
    if [[ "$reserved" == *" $seg "* ]] &&
      { [[ ! "$after" =~ ^[A-Za-z0-9._-] ]] || [[ "$after" =~ ^\.([^A-Za-z0-9_-]|$) ]]; }; then
      rest="$after"
      continue
    fi
    return 0
  done
  return 1
}

audit_noise_follower_is_document_locator() {
  local head="${1,,}"
  [[ -z "${head//[[:space:]]/}" ]] && return 0
  head="${head#"${head%%[![:space:]]*}"}"
  head="${head%%,*}"
  head="${head%%;*}"
  head="${head%%. *}"
  [[ -z "${head//[[:space:]]/}" ]] && return 0
  [[ "$head" == '['* || "$head" == *'§'* || "$head" == '#'[a-z]* ]] && return 0
  [[ "${head%% *}" == */* ]] && return 0
  [[ "$head" =~ (^|[^a-z])(section|sections|chapter|chapters|appendix|step|steps|table|tables|figure|paragraph|adr|adrs|rfc|rfcs|spec|specs|specification|readme|changelog|convention|conventions|guide|schema|doc|docs|document|documentation)([^a-z]|$) ]] && return 0
  return 1
}

audit_noise_line_has_conversational_antecedent() {
  local line="$1" rest follower
  [[ "$line" =~ [Pp]er[[:space:]]+your[[:space:]]+request ]] && return 0
  [[ "$line" =~ [Pp]er[[:space:]]+our[[:space:]]+(conversation|discussion|chat) ]] && return 0
  [[ "$line" =~ [Ll]ike[[:space:]]+you[[:space:]]+said ]] && return 0
  [[ "$line" =~ (^|[^A-Za-z])[Aa]s[[:space:]]+requested[[:space:]]*([,;:.!?]|\)|$) ]] && return 0
  if [[ "$line" =~ [Aa]s[[:space:]]+(you|we)(\'ve|\'d|’ve|’d)?[[:space:]]+(asked|requested|discussed|agreed|decided)(.*)$ ]]; then
    rest="${BASH_REMATCH[4]}"
    if [[ "$rest" =~ ^[[:space:]]+([A-Za-z]+)(.*)$ ]]; then
      follower="${BASH_REMATCH[1],,}"
      rest="${BASH_REMATCH[2]}"
      case "$follower" in
      above | below | earlier | later | previously | elsewhere) return 1 ;;
      in | under | at | on) audit_noise_follower_is_document_locator "$rest" && return 1 ;;
      *) ;;
      esac
    fi
    return 0
  fi
  return 1
}

audit_noise_line_has_plan_reference() {
  local line="$1"
  [[ "$line" =~ [Rr]eplaces[[:space:]]+the[[:space:]]+old ]] && return 0
  [[ "$line" =~ [Ii]n[[:space:]]+this[[:space:]]+(PR|MR|pull[[:space:]]+request|commit|changeset|refactor),?[[:space:]]+(we|I)(\'ve|\'re|\'ll|\'d|\'m|’ve|’re|’ll|’d|’m)?[[:space:]] ]] && return 0
  [[ "$line" =~ ([Tt]ask|[Pp]hase|[Ss]tep)[[:space:]]+#?[0-9]+[[:space:]]+(of|in)[[:space:]]+(the|this)[[:space:]]+plan ]] && return 0
  return 1
}

audit_noise_line_is_tracked_work() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+\[[[:space:]xX]\][[:space:]] ]] && return 0
  [[ "$line" =~ (TODO|FIXME|HACK|XXX)[[:space:]]*\(#?[A-Za-z0-9_-]+\) ]] && return 0
  return 1
}

audit_noise_line_has_ticket_pr_residue() {
  local line="$1"
  audit_noise_line_is_tracked_work "$line" && return 1
  [[ "$line" =~ [Ss]ee[[:space:]]+(the[[:space:]]+)?(PR|MR|pull[[:space:]]+request|issue|ticket)[[:space:]]*#?[0-9] ]] && return 0
  [[ "$line" =~ ([Ii]ntroduced|[Aa]dded|[Ll]anded|[Ss]hipped|[Ff]ixed|[Rr]everted|[Dd]ecided|[Aa]greed)[[:space:]]+in[[:space:]]+(PR|MR|issue|ticket)[[:space:]]*#?[0-9] ]] && return 0
  [[ "$line" =~ [Tt]racked[[:space:]]+in[[:space:]]+#[0-9] ]] && return 0
  [[ "$line" =~ ([Tt]racked|[Ff]iled|[Ll]ogged|[Rr]eported)[[:space:]]+(in|as|under)[[:space:]]+[A-Z][A-Z0-9]+-[0-9] ]] && return 0
  [[ "$line" =~ [Ff]rom[[:space:]]+the[[:space:]]+feature[[:space:]]+branch ]] && return 0
  return 1
}

audit_noise_line_has_preamble() {
  local line="$1"
  [[ "$line" =~ ^#{1,6}[[:space:]]+(Why[[:space:]]+this[[:space:]]+file[[:space:]]+exists|Motivation|Rationale)([^[:alnum:]]|$) ]]
}

audit_noise_line_has_citation() {
  local line="$1"
  [[ "$line" =~ [Ee]mpirically[[:space:]]+observed ]] && return 0
  [[ "$line" =~ [Ww]e[[:space:]]+pivoted[[:space:]]+from ]] && return 0
  [[ "$line" =~ [Ww]as[[:space:]]+renamed[[:space:]]+to ]] && return 0
  [[ "$line" =~ [Rr]enamed[[:space:]]+from ]] && return 0
  [[ "$line" =~ [Pp]re-convention ]] && return 0
  [[ "$line" =~ [Ll]egacy[[:space:]]+layout ]] && return 0
  if [[ ! "$line" =~ (https?://|\]\(|\]\[) ]]; then
    [[ "$line" =~ (^|^[[:space:]]*[-*+][[:space:]]+|[,\;:][[:space:]]+|\([[:space:]]*)([Pp]orted|[Cc]opied|[Mm]igrated|[Aa]dapted|[Bb]orrowed|[Ll]ifted|[Tt]aken)[[:space:]]+from([^[:alnum:]]|$) ]] && return 0
    [[ "$line" =~ (^|^[[:space:]]*[-*+][[:space:]]+|[,\;:][[:space:]]+)([Aa]dded|[Mm]erged|[Ii]ntroduced|[Bb]ackported|[Pp]orted)[[:space:]]+(on[[:space:]]+)?[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt][0-9:]{4,8}[Zz]?)?([^[:alnum:]]|$) ]] && return 0
  fi
  return 1
}

audit_noise_line_has_enum_list() {
  local stripped="$1" unwrapped="$2"
  [[ "$stripped" =~ [Ff]ollowing[[:space:]]+([0-9]+|two|three|four|five|six|seven|eight|nine|ten)[[:space:]]+(skills|consumers|agents|modules|plugins) ]] && return 0
  [[ "$unwrapped" =~ ^[[:space:]]*[-*+][[:space:]]+/[a-z][a-z0-9_-]*[[:space:]]+(—|–|--|-) ]] && return 0
  [[ "$unwrapped" =~ ^[[:space:]]*[-*+][[:space:]]+\*\*[^*]+[[:space:]]*— ]] && return 0
  [[ "$unwrapped" =~ ^[[:space:]]*[-*+][[:space:]]+\*\*[^*]+\*\*[[:space:]]+(—|–|--) ]] && return 0
  if [[ "$unwrapped" =~ ^[[:space:]]*\| ]] &&
    [[ ! "$unwrapped" =~ ^[[:space:]]*\|[[:space:]]*:?-{2,} ]] &&
    [[ "$unwrapped" =~ /[a-z][a-z0-9_-]+ ]]; then
    return 0
  fi
  return 1
}

audit_noise_detect_shapes_into() {
  local -n _audit_noise_shapes_out="$1"
  local line="$2"
  local unwrapped="" stripped=""
  _audit_noise_shapes_out=()
  audit_noise_unwrap_backticks "$line" unwrapped
  audit_noise_strip_inline_code "$line" stripped
  if audit_noise_line_has_ghost_ref "$unwrapped"; then
    _audit_noise_shapes_out+=('ghost-ref')
  fi
  if audit_noise_line_has_preamble "$stripped"; then
    _audit_noise_shapes_out+=('preamble')
  fi
  if audit_noise_line_has_citation "$stripped"; then
    _audit_noise_shapes_out+=('citation')
  fi
  if audit_noise_line_has_enum_list "$stripped" "$unwrapped"; then
    _audit_noise_shapes_out+=('enum-list')
  fi
  if [[ "$stripped" =~ [Pp]ath-scoped[[:space:]]+to ]] ||
    [[ "$stripped" =~ [Ll]oads[[:space:]]+on[[:space:]]+[Rr]ead[[:space:]]+of ]] ||
    [[ "$stripped" =~ [Aa]uto-loads[[:space:]]+when ]]; then
    _audit_noise_shapes_out+=('scope-meta')
  fi
  if audit_noise_line_has_plan_reference "$stripped"; then
    _audit_noise_shapes_out+=('plan-reference')
  fi
  if audit_noise_line_has_conversational_antecedent "$stripped"; then
    _audit_noise_shapes_out+=('conversational-antecedent')
  fi
  if audit_noise_line_has_ticket_pr_residue "$stripped"; then
    _audit_noise_shapes_out+=('ticket-pr-residue')
  fi
  if [[ "${3:-}" != "skip-negation" ]]; then
    if audit_noise_line_has_negation_without_positive "$unwrapped"; then
      _audit_noise_shapes_out+=('negation')
    fi
  fi
  ((${#_audit_noise_shapes_out[@]} > 0))
}

audit_noise_shape_tier() {
  local tier
  audit_noise_shape_tier_into "$1" tier
  printf '%s' "$tier"
}

audit_noise_shape_tier_into() {
  local shape="$1"
  local -n _audit_noise_tier_out="$2"
  case "$shape" in
  ghost-ref | preamble | ticket-pr-residue | negation) _audit_noise_tier_out=2 ;;
  citation | enum-list | scope-meta | plan-reference | conversational-antecedent) _audit_noise_tier_out=1 ;;
  *) _audit_noise_tier_out=3 ;;
  esac
}

audit_noise_section_exempt() {
  local heading="$1"
  heading="${heading#"${heading%%[![:space:]]*}"}"
  heading="${heading%"${heading##*[![:space:]]}"}"
  if [[ "$heading" =~ ^(.*[^#[:space:]])[[:space:]]*#+[[:space:]]*$ ]]; then
    heading="${BASH_REMATCH[1]}"
  fi
  case "$heading" in
  "Recheck triggers" | "Cross-references" | "Sources" | "History" | "External authority") return 0 ;;
  "Reference index. Load on demand" | "Context ladder (read on demand)" | "Maintenance. Load on demand") return 0 ;;
  *) ;;
  esac
  [[ "$heading" == *"amendment"* ]] && return 0
  return 1
}

audit_noise_unwrap_backticks() {
  local line="$1"
  local -n _audit_noise_unwrapped_out="$2"
  _audit_noise_unwrapped_out="${line//\`/}"
}

audit_noise_strip_inline_code() {
  local line="$1"
  local -n _audit_noise_stripped_out="$2"
  local out="" rest="$line" pre
  while [[ "$rest" == *'`'* ]]; do
    pre="${rest%%\`*}"
    rest="${rest#*\`}"
    if [[ "$rest" == *'`'* ]]; then
      out+="$pre"
      rest="${rest#*\`}"
    else
      out+="$pre\`$rest"
      rest=""
      break
    fi
  done
  out+="$rest"
  _audit_noise_stripped_out="$out"
}

audit_noise_is_ignore_line_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore-line[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}

audit_noise_is_ignore_para_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}

audit_noise_split_sentences_into() {
  local -n _audit_noise_sentences_out="$1"
  local rest="$2"
  local tail_parts=() i
  _audit_noise_sentences_out=()
  while [[ "$rest" =~ ^(.*[.!?])[[:space:]]+(.*)$ ]]; do
    tail_parts+=("${BASH_REMATCH[2]}")
    rest="${BASH_REMATCH[1]}"
  done
  [[ -n "${rest//[[:space:]]/}" ]] && _audit_noise_sentences_out+=("$rest")
  for ((i = ${#tail_parts[@]} - 1; i >= 0; i--)); do
    [[ -n "${tail_parts[i]//[[:space:]]/}" ]] && _audit_noise_sentences_out+=("${tail_parts[i]}")
  done
  return 0
}

AUDIT_NOISE_APOS="['’]"

AUDIT_NOISE_PROHIBITION_ALT="never|do[[:space:]]+not|don${AUDIT_NOISE_APOS}t|avoid|must[[:space:]]+not|should[[:space:]]+not|shouldn${AUDIT_NOISE_APOS}t"

audit_noise_sentence_has_prohibition() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(${AUDIT_NOISE_PROHIBITION_ALT})([^[:alnum:]]|$) ]]
}

audit_noise_sentence_has_positive_pairing() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(instead|rather[[:space:]]+than|prefer(s|red|ring)?|in[[:space:]]+place[[:space:]]+of|in[[:space:]]+favou?r[[:space:]]+of)([^[:alnum:]]|$) ]]
}

AUDIT_NOISE_CLAUSE_STOPWORDS=" the a an and or but nor so yet if unless until when while where which who whose that this these those it its they their them we our us you your he she his her i is are was were be been being as at by for from in into of on onto to with without not no never nor don't do does did doing ever even because since though although however therefore thus hence per via plus minus other others such same both all any each every more most less least than there here what how why "

AUDIT_NOISE_CLAUSE_TRANSPARENT=" just simply always then also still only first next now again finally "

audit_noise_clause_names_alternative() {
  local body="$1" seg first
  body="${body//\*\*/}"
  body="${body//__/}"
  body="${body//; /$'\n'}"
  body="${body//: /$'\n'}"
  body="${body//, /$'\n'}"
  body="${body//—/$'\n'}"
  body="${body//–/$'\n'}"
  body="${body// -- /$'\n'}"
  local firstseg=1
  while IFS= read -r seg; do
    if ((firstseg)); then
      firstseg=0
      continue
    fi
    while :; do
      seg="${seg#"${seg%%[![:space:]]*}"}"
      case "$seg" in
      \**) seg="${seg#\*}" ;;
      _*) seg="${seg#_}" ;;
      \[*) seg="${seg#\[}" ;;
      *) break ;;
      esac
    done
    while :; do
      first="${seg%%[!A-Za-z\']*}"
      [[ -n "$first" ]] || break
      first="${first,,}"
      if [[ "$AUDIT_NOISE_CLAUSE_TRANSPARENT" == *" $first "* && "$seg" == *[[:space:]]* ]]; then
        seg="${seg#*[[:space:]]}"
        seg="${seg#"${seg%%[![:space:]]*}"}"
        continue
      fi
      break
    done
    [[ -n "$first" ]] || continue
    [[ "$AUDIT_NOISE_CLAUSE_TRANSPARENT" == *" $first "* ]] && continue
    [[ "$AUDIT_NOISE_CLAUSE_STOPWORDS" == *" $first "* ]] && continue
    if audit_noise_sentence_opens_with_prohibition "$seg"; then
      continue
    fi
    return 0
  done <<<"$body"
  return 1
}

audit_noise_sentence_has_hard_guardrail() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(secrets?|credentials?|tokens?|passwords?|api[[:space:]]+keys?|force-push(es|ed|ing)?|force[[:space:]]+push(es|ed|ing)?|--force|rm[[:space:]]+-rf|destructive|irreversible|data[[:space:]]+loss|production|security|vulnerab[a-z]*|rewrite[[:space:]]+history)([^[:alnum:]]|$) ]]
}

audit_noise_sentence_is_worked_example() {
  [[ "$1" == *'→'* || "$1" == *'->'* ]]
}

audit_noise_strip_line_lead() {
  local s="$1"
  local -n _audit_noise_lead_out="$2"
  local lead_re='^([-*+]|[0-9]+[.)]|>|\[[[:space:]xX]\])[[:space:]]*'
  s="${s#"${s%%[![:space:]]*}"}"
  while [[ "$s" =~ $lead_re ]]; do
    s="${s#"${BASH_REMATCH[0]}"}"
    s="${s#"${s%%[![:space:]]*}"}"
  done
  while [[ "$s" =~ ^(\*\*\*|\*\*|\*|___|__|_) ]]; do
    s="${s#"${BASH_REMATCH[0]}"}"
  done
  _audit_noise_lead_out="$s"
}

audit_noise_sentence_opens_with_prohibition() {
  local lead=""
  audit_noise_strip_line_lead "$1" lead
  local s="${lead,,}"
  [[ "$s" =~ ^(${AUDIT_NOISE_PROHIBITION_ALT})([^[:alnum:]]|$) ]]
}

audit_noise_line_ends_sentence() {
  local s="$1"
  s="${s%"${s##*[![:space:]]}"}"
  [[ "$s" =~ [.!?](\*\*\*|\*\*|\*|___|__|_|\)|\"|\'|’)*$ ]]
}

AUDIT_NOISE_FIRED_MARKER=""

audit_noise_line_has_negation_without_positive() {
  local sentences=() s lower m
  local mode="${2:-line}"
  AUDIT_NOISE_FIRED_MARKER=""
  if [[ "$mode" == "line" ]]; then
    audit_noise_line_ends_sentence "$1" || return 1
  fi
  audit_noise_split_sentences_into sentences "$1"
  for s in "${sentences[@]}"; do
    audit_noise_sentence_opens_with_prohibition "$s" || continue
    audit_noise_sentence_has_prohibition "$s" || continue
    audit_noise_sentence_has_positive_pairing "$s" && continue
    audit_noise_clause_names_alternative "$s" && continue
    audit_noise_sentence_has_hard_guardrail "$s" && continue
    audit_noise_sentence_is_worked_example "$s" && continue
    lower="${s,,}"
    for m in never "do not" "must not" "should not" avoid; do
      if [[ "$lower" == *"$m"* ]]; then
        AUDIT_NOISE_FIRED_MARKER="$m"
        break
      fi
    done
    [[ -n "$AUDIT_NOISE_FIRED_MARKER" ]] || AUDIT_NOISE_FIRED_MARKER="dont"
    return 0
  done
  return 1
}
