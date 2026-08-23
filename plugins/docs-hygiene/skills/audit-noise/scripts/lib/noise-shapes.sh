# shellcheck shell=bash
# Shared noise-shape detectors for /audit-noise (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Noise shapes and treatments".

audit_noise_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  # Prefer nameref when the caller wants to avoid a command-substitution subshell.
  if [[ -n "${2:-}" ]]; then
    local -n _audit_noise_excerpt_out="$2"
    _audit_noise_excerpt_out="$line"
    return 0
  fi
  printf '%s' "$line"
}

# Resolve configured convention roots once per process and export them.
# Calling this (or the legacy pattern helper) inside a command substitution used
# to set AUDIT_NOISE_CONTRACT_ROOT only in the subshell — so a configured
# contract root's bare reviews/handoffs/running-retros child was silently
# exempt against the lib's stated intent (auditor F6).
audit_noise_resolve_convention_roots() {
  if [[ -n "${AUDIT_NOISE_ROOTS_RESOLVED:-}" ]]; then
    return 0
  fi
  local pattern='\.work|docs/topics' key val yaml lib_dir
  yaml="${AUDIT_NOISE_REPO_ROOT:-.}/.claude/topic-docs.yaml"
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Default contract root matches the built-in pattern default.
  AUDIT_NOISE_CONTRACT_ROOT="${AUDIT_NOISE_CONTRACT_ROOT:-docs/topics}"
  if [[ -f "$yaml" ]]; then
    for key in memory_dir contract_dir; do
      val=$("$lib_dir/parse-concern-value.sh" "$yaml" "$key")
      if [[ "$key" == 'contract_dir' && -n "$val" ]]; then
        AUDIT_NOISE_CONTRACT_ROOT="$val"
      fi
      if [[ -n "$val" && "$val" != '.' && "$val" != '.work' && "$val" != 'docs/topics' ]]; then
        pattern+="|$(printf '%s' "$val" | sed "s/[.[\\*^\$()+?{|]/\\\\&/g")"
      fi
    done
  fi
  AUDIT_NOISE_ROOTS_PATTERN="$pattern"
  AUDIT_NOISE_ROOTS_RESOLVED=1
  export AUDIT_NOISE_ROOTS_PATTERN AUDIT_NOISE_CONTRACT_ROOT AUDIT_NOISE_ROOTS_RESOLVED
}

# Back-compat wrapper: ensure roots are resolved, then print the pattern.
# Prefer audit_noise_resolve_convention_roots + $AUDIT_NOISE_ROOTS_PATTERN in
# hot paths so the assignment cannot be lost to a subshell.
audit_noise_convention_roots_pattern() {
  audit_noise_resolve_convention_roots
  printf '%s' "$AUDIT_NOISE_ROOTS_PATTERN"
}

# Per-match ghost-ref scan: exemptions apply to each matched path, never to
# the whole line, so a convention token cannot mask a concrete ghost ref
# sharing its line. Angle-bracket slot variables (root followed by '<') are
# schema placeholders and never match the candidate pattern; the reserved
# concern-scoped roots (<memory_dir>/handoffs/, <memory_dir>/reviews/,
# <memory_dir>/running-retros/, <memory_dir>/overengineering/ — reserved
# first-level names under the memory root per docs/conventions/topic-docs/)
# are exempt only in bare form — a
# concrete child under them flags. Configured non-default roots from the
# concern file scan alongside the defaults. The bare-root exemption is for
# memory roots only — never for the contract root (default or configured).
audit_noise_line_has_ghost_ref() {
  local rest="$1" path root seg after roots
  audit_noise_resolve_convention_roots
  # Retired locations: stale even in placeholder form.
  [[ "$rest" == *'.claude/notes/'* ||
    "$rest" == *'.claude/handoffs/'* ||
    "$rest" == *'.claude/review/'* ]] && return 0
  roots="$AUDIT_NOISE_ROOTS_PATTERN"
  while [[ "$rest" =~ ($roots)/([a-z0-9][a-z0-9_-]*)/ ]]; do
    path="${BASH_REMATCH[0]}"
    root="${BASH_REMATCH[1]}"
    seg="${BASH_REMATCH[2]}"
    after="${rest#*"$path"}"
    # Bare-root exemption: nothing concrete after the trailing slash. A
    # sentence-ending period (`.work/running-retros/.`) starts with `.` but is
    # punctuation, not a hidden child — only `.` followed by a path segment
    # character counts as concrete (`.gitignore`-style names still flag).
    if [[ "$root" != 'docs/topics' && "$root" != "$AUDIT_NOISE_CONTRACT_ROOT" ]] &&
      [[ "$seg" == 'handoffs' || "$seg" == 'reviews' || "$seg" == 'running-retros' || "$seg" == 'overengineering' ]] &&
      { [[ ! "$after" =~ ^[A-Za-z0-9._-] ]] || [[ "$after" =~ ^\.([^A-Za-z0-9_-]|$) ]]; }; then
      rest="$after"
      continue
    fi
    return 0
  done
  return 1
}

# True when a line is a BARE prohibition: an imperative negation whose own
# sentence names no positive alternative. `write-for-agents` "Prompt the
# positive" is the write-side rule this is the audit side of — keep a negation
# only when the positive form loses the constraint, and then pair it with the
# positive IN THE SAME SENTENCE.
#
# Scope is deliberately the decidable core, and the narrowing is what keeps the
# false-positive rate survivable in an instruction-heavy corpus:
#
#   * The cue must be LINE-INITIAL (after list, blockquote and emphasis
#     markers), so descriptive negations ("the script does not read X") never
#     select. Only an imperative prohibition does.
#   * The line must END its sentence (`.`, `!`, `?`). This repo hard-wraps
#     prose, so a continuation line cannot be shown to lack a positive that
#     sits on the next line — the pairing rule is per SENTENCE, and only a
#     sentence-terminating line is one this scanner can decide. A table row
#     ends in `|` and is excluded by the same test.
#
# A mid-sentence prohibition ("Prefer X; never Y") is out of scope in v1 by
# construction: correctly paired prose puts the cue after the positive, so the
# line-initial test already declines it.
audit_noise_line_is_bare_negation() {
  local line="$1" stripped body
  audit_noise_strip_inline_code "$line" stripped
  stripped="${stripped//$'\r'/}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  [[ "$stripped" =~ [.!?]$ ]] || return 1
  body="${stripped#"${stripped%%[![:space:]]*}"}"
  # Peel list / blockquote markers, then leading emphasis runs.
  while [[ "$body" =~ ^(\>|[-*+]|[0-9]+[.\)])[[:space:]]+ ]]; do
    body="${body#"${BASH_REMATCH[0]}"}"
  done
  body="${body#\*\*}"
  body="${body#\*}"
  body="${body#__}"
  body="${body#_}"
  [[ "$body" =~ ^(Do[[:space:]]not|Do[[:space:]]NOT|Don\'t|Never|Avoid)[[:space:]]+([^[:space:]]+) ]] || return 1
  # `Never`/`Avoid` also open THIRD-PERSON prose ("Never audits a target that
  # is not a git repository"), which is a capability roster describing what a
  # component does — not an instruction to anyone. An imperative never takes
  # the third-person `-s`, so a following verb in that form declines the line.
  # Imperatives ending in a doubled or vowel-led `s` (process, discuss, focus,
  # bypass, bias) are excluded from the test rather than caught by it.
  local nextword="${BASH_REMATCH[2]}"
  nextword="${nextword%%[!A-Za-z-]*}"
  case "$nextword" in
  *[!suioa]s) return 1 ;;
  *) ;;
  esac
  # A positive target riding the same sentence keeps the negation, and the two
  # explicit contrast words are the unambiguous half of that test.
  # Spelled as whole alternatives, not as the leading-character-class idiom the
  # other shapes use: the repo's typos gate reads the remainder a class-split
  # leaves behind as a misspelled word.
  [[ "$body" =~ (instead|Instead|rather|Rather|prefer|Prefer) ]] && return 1
  audit_noise_clause_names_alternative "$body" && return 1
  return 0
}

# Function words that open a CONTINUATION or a CONSEQUENCE rather than a
# positive alternative. The list is closed and short on purpose: testing what a
# following clause is NOT generalizes, where an allow-list of imperative verbs
# only ever covers the verbs its author happened to think of.
AUDIT_NOISE_CLAUSE_STOPWORDS=" the a an and or but nor so yet if unless until when while where which who whose that this these those it its they their them we our us you your he she his her i is are was were be been being as at by for from in into of on onto to with without not no never nor don't do does did doing ever even because since though although however therefore thus hence per via plus minus other others such same both all any each every more most less least than there here what how why "

# Adverbs that lead an imperative without being one ("Just mark.", "Simply
# re-run it."). The word after them decides the clause, so the test looks
# THROUGH these rather than stopping on them — treating them as stopwords
# reported a positive alternative as if it were absent.
AUDIT_NOISE_CLAUSE_TRANSPARENT=" just simply always then also still only first next now again finally "

# True when a clause after a separator opens with a content word — the signal
# that the sentence names something to DO alongside the thing it forbids.
# Sentence boundaries inside the line count as separators, so a prohibition
# whose alternative rides the next sentence of the same line is not reported.
audit_noise_clause_names_alternative() {
  local body="$1" seg first
  # Emphasis runs sit BETWEEN a sentence terminator and its following space
  # ("…dialog.** Leave it open."), so stripping them globally first is what
  # lets the sentence split see that boundary at all.
  body="${body//\*\*/}"
  body="${body//__/}"
  # The separator is a GLOB here, so `?` must be escaped — unescaped it matches
  # any single character and shreds the clause into two-letter fragments.
  body="${body//; /$'\n'}"
  body="${body//: /$'\n'}"
  body="${body//, /$'\n'}"
  body="${body//. /$'\n'}"
  body="${body//\? /$'\n'}"
  body="${body//! /$'\n'}"
  body="${body//—/$'\n'}"
  body="${body// -- /$'\n'}"
  local firstseg=1
  while IFS= read -r seg; do
    if ((firstseg)); then
      firstseg=0
      continue
    fi
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg#\*}"
    while :; do
      first="${seg%%[!A-Za-z\']*}"
      [[ -n "$first" ]] || break
      first="${first,,}"
      # A transparent adverb with nothing after it ends the clause rather than
      # looking through to a next word that does not exist.
      if [[ "$AUDIT_NOISE_CLAUSE_TRANSPARENT" == *" $first "* && "$seg" == *[[:space:]]* ]]; then
        seg="${seg#*[[:space:]]}"
        continue
      fi
      break
    done
    [[ -n "$first" ]] || continue
    # A transparent adverb the loop could not look THROUGH (nothing follows it)
    # names no alternative either — "Never do X, just." must still report.
    [[ "$AUDIT_NOISE_CLAUSE_TRANSPARENT" == *" $first "* ]] && continue
    [[ "$AUDIT_NOISE_CLAUSE_STOPWORDS" == *" $first "* ]] && continue
    return 0
  done <<<"$body"
  return 1
}

# Append matching shape names into the nameref array (avoids a per-line
# command-substitution subshell in the detect hot loop).
# Ghost-ref scans an unwrap (ticks removed, content kept); other shapes scan a
# strip (inline-code spans removed) so schema examples do not self-match.
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
  if [[ "$stripped" =~ ^##[[:space:]]+Why[[:space:]]+this[[:space:]]+file[[:space:]]+exists ]]; then
    _audit_noise_shapes_out+=('preamble')
  fi
  if [[ "$stripped" =~ [Ee]mpirically[[:space:]]+observed ]] ||
    [[ "$stripped" =~ [Ww]e[[:space:]]+pivoted[[:space:]]+from ]] ||
    [[ "$stripped" =~ [Ww]as[[:space:]]+renamed[[:space:]]+to ]] ||
    [[ "$stripped" =~ [Pp]re-convention ]] ||
    [[ "$stripped" =~ [Ll]egacy[[:space:]]+layout ]]; then
    _audit_noise_shapes_out+=('citation')
  fi
  if [[ "$stripped" =~ [Ff]ollowing[[:space:]]+(five|four|three|six|seven|eight|nine|ten|[0-9]+)[[:space:]]+(skills|consumers|agents|modules) ]]; then
    _audit_noise_shapes_out+=('enum-list')
  fi
  # Enum roster lines often wrap the slash-command in backticks; match the
  # unwrapped form so `- `/skill`` still counts after tick removal.
  if [[ "$unwrapped" =~ ^[[:space:]]*-[[:space:]]+/[a-z][a-z0-9_-]*[[:space:]]— ]]; then
    _audit_noise_shapes_out+=('enum-list')
  fi
  if [[ "$stripped" =~ [Pp]ath-scoped[[:space:]]+to ]] ||
    [[ "$stripped" =~ [Ll]oads[[:space:]]+on[[:space:]]+[Rr]ead[[:space:]]+of ]] ||
    [[ "$stripped" =~ [Aa]uto-loads[[:space:]]+when ]]; then
    _audit_noise_shapes_out+=('scope-meta')
  fi
  if audit_noise_line_is_bare_negation "$line"; then
    _audit_noise_shapes_out+=('negation-without-positive')
  fi
  ((${#_audit_noise_shapes_out[@]} > 0))
}

# Emit zero or more shape names (one per line on stdout). Prefer
# audit_noise_detect_shapes_into in hot loops.
audit_noise_detect_shapes() {
  local shapes=()
  if audit_noise_detect_shapes_into shapes "$1"; then
    local s
    for s in "${shapes[@]}"; do
      printf '%s\n' "$s"
    done
    return 0
  fi
  return 1
}

audit_noise_shape_tier() {
  local shape="$1"
  case "$shape" in
  ghost-ref | preamble | negation-without-positive) printf '2' ;;
  citation | enum-list | scope-meta) printf '1' ;;
  *) printf '3' ;;
  esac
}

# Set nameref to the tier digit without a subshell.
audit_noise_shape_tier_into() {
  local shape="$1"
  local -n _audit_noise_tier_out="$2"
  case "$shape" in
  ghost-ref | preamble | negation-without-positive) _audit_noise_tier_out=2 ;;
  citation | enum-list | scope-meta) _audit_noise_tier_out=1 ;;
  *) _audit_noise_tier_out=3 ;;
  esac
}

# True when an ATX heading's visible title (any level) is an exempt section.
# Callers pass the text after the opening hashes; trailing closing hashes and
# surrounding whitespace are stripped here.
audit_noise_section_exempt() {
  local heading="$1"
  heading="${heading#"${heading%%[![:space:]]*}"}"
  heading="${heading%"${heading##*[![:space:]]}"}"
  # ATX may close with trailing hashes: "## Sources ##"
  if [[ "$heading" =~ ^(.*[^#[:space:]])[[:space:]]*#+[[:space:]]*$ ]]; then
    heading="${BASH_REMATCH[1]}"
  fi
  heading="${heading%"${heading##*[![:space:]]}"}"
  case "$heading" in
  "Recheck triggers" | "Cross-references" | "Sources" | "History" | "External authority") return 0 ;;
  *) ;;
  esac
  [[ "$heading" == *"amendment"* ]] && return 0
  return 1
}

# Remove backtick characters only (unwrap inline code) so path cites like
# `.work/foo/PLAN.md` still reach the ghost-ref detector.
audit_noise_unwrap_backticks() {
  local line="$1"
  local -n _audit_noise_unwrapped_out="$2"
  _audit_noise_unwrapped_out="${line//\`/}"
}

# Strip inline `code` spans entirely so citation / enum / scope detectors do
# not self-match examples. Fence blocks are skipped by the caller.
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
      # Unclosed tick — keep the remainder literally.
      out+="$pre\`$rest"
      rest=""
      break
    fi
  done
  out+="$rest"
  _audit_noise_stripped_out="$out"
}

# True when the line is a well-formed HTML opt-out marker comment (not a
# prose mention of the marker name).
audit_noise_is_ignore_line_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore-line[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}

audit_noise_is_ignore_para_marker() {
  [[ "$1" =~ ^[[:space:]]*\<!--[[:space:]]*markdown-discipline-ignore[[:space:]]*--\>[[:space:]]*$ ]] # portability-ok: bash [[ =~ ]] ERE escapes for literal < >, not GNU grep word-boundary
}
