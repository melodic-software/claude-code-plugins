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
  # TRAILING emphasis hides the terminator from the test below — a fully bolded
  # directive (`**Never edit the generated file.**`) ends in `*`, not in `.`,
  # and bolded directives are everywhere in this corpus. Peel before testing.
  while [[ "$stripped" == *[\*_] ]]; do
    stripped="${stripped%[\*_]}"
  done
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
  # Both apostrophes: a curly one is what a chat-interface paste leaves behind,
  # and it is already present in this corpus.
  # Spelled as two alternatives, not a bracket expression: a multibyte curly
  # apostrophe inside `[...]` is matched byte-wise and never fires.
  [[ "$body" =~ ^(Do[[:space:]]not|Do[[:space:]]NOT|Don\'t|Don’t|Never|Avoid)[[:space:]]+([^[:space:]]+) ]] || return 1
  # `Never` also opens THIRD-PERSON prose ("Never audits a target that is not
  # a git repository"), which is a capability roster describing what a
  # component does — not an instruction to anyone. An imperative never takes
  # the third-person `-s`, so a following verb in that form declines the line.
  # Imperatives ending in a doubled or vowel-led `s` (process, discuss, focus,
  # bypass, bias) are excluded from the test rather than caught by it.
  #
  # Scoped to `Never` ON PURPOSE. Applied to `Avoid`, the same test reads a
  # PLURAL NOUN as a third-person verb and drops real imperatives — measured on
  # this repo: `Avoid conditions the transcript cannot show.` and `Avoid
  # identities and marked cliches unless the line renews them.` Every capability
  # roster this shape must decline opens with `Never`, so narrowing loses
  # nothing, and the admission test wants an unresolved case to EMIT.
  local cue="${BASH_REMATCH[1]}" nextword="${BASH_REMATCH[2]}"
  if [[ "$cue" == "Never" ]]; then
    nextword="${nextword%%[!A-Za-z-]*}"
    case "$nextword" in
    *[!suioa]s) return 1 ;;
    *) ;;
    esac
  fi
  # A positive target riding the same sentence keeps the negation, and the three
  # explicit contrast words are the unambiguous half of that test.
  #
  # WORD-ANCHORED. An unanchored substring test declines every sentence carrying
  # "preferred", "preference" or "gathered" although no contrast word is present
  # — withholding a finding on evidence the rule never had. Matched lowercased
  # through a `case` glob rather than a leading-character-class regex, which the
  # repo's typos gate reads as a misspelling.
  local lower=" ${body,,} "
  case "$lower" in
  *[!a-z]instead[!a-z]* | *[!a-z]rather[!a-z]* | *[!a-z]prefer[!a-z]*) return 1 ;;
  *) ;;
  esac
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
    # Peel leading whitespace and the emphasis / link-open characters a clause
    # can start with. Without this the segment keeps a non-letter lead, its
    # first word reads as empty, the clause is dropped, and the line FIRES
    # although it named an alternative — `_Read it_ from the environment.` and
    # `[Read the guide](docs/guide.md) for the shape.` are both real forms.
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
      # A transparent adverb with nothing after it ends the clause rather than
      # looking through to a next word that does not exist.
      if [[ "$AUDIT_NOISE_CLAUSE_TRANSPARENT" == *" $first "* && "$seg" == *[[:space:]]* ]]; then
        seg="${seg#*[[:space:]]}"
        # Re-strip: the peel removes ONE whitespace character, so a
        # double-spaced clause would keep a leading space and be dropped.
        seg="${seg#"${seg%%[![:space:]]*}"}"
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

# --- Prose-adapted residue shapes -------------------------------------------
#
# plan-reference, conversational-antecedent, and ticket-pr-residue carry the
# same shape names the code-side sibling (/code-tidying:audit-comment-residue)
# owns, but the patterns are deliberately TIGHTER, not copies. That scanner
# classifies only the extracted comment portion of a line; this one classifies
# whole markdown prose, where the same words are load-bearing far more often.
# All three scan the inline-code strip, so a shape-definition example written
# in backticks does not self-match.

# True when the text following an antecedent's `in` names a written locus a
# future reader can still open — a position inside this page, or a named
# durable document — rather than the conversation or circumstance the sentence
# came out of. The input is the raw follower text: it is lowercased here (the
# follower used to be compared case-sensitively, so a capitalised one fell
# through) and cut at the first clause break, so a locator noun in a LATER
# clause cannot exempt the antecedent. Two deliberate absences: tracker nouns
# (`issue`, `ticket`, `PR`) — a decision parked in a tracker is provenance,
# which ticket-pr-residue owns and this shape must not launder — and nouns for
# the conversation itself (`meeting`, `call`, `thread`, `review`), which are
# the residue. `part` and `phase` are absent too: "in part" is an idiom, and a
# phase is a stage of work, not a place in a document.
audit_noise_follower_is_document_locator() {
  local head="${1,,}"
  # Empty: an inline-code reference (`docs/x.md`) the strip removed, or a line
  # that ends on the preposition. Both are references, not conversation.
  [[ -z "${head//[[:space:]]/}" ]] && return 0
  head="${head#"${head%%[![:space:]]*}"}"
  head="${head%%,*}"
  head="${head%%;*}"
  head="${head%%. *}"
  # A markdown link, a section sign, or a path is a locus outright. `#` counts
  # only ahead of a letter: `#anchor` is an anchor, `#482` is a tracker ref.
  [[ "$head" == '['* || "$head" == *'§'* || "$head" == '#'[a-z]* ]] && return 0
  [[ "${head%% *}" == */* ]] && return 0
  [[ "$head" =~ (^|[^a-z])(section|sections|chapter|chapters|appendix|step|steps|table|tables|figure|paragraph|adr|adrs|rfc|rfcs|spec|specs|specification|readme|changelog|convention|conventions|guide|schema|doc|docs|document|documentation)([^a-z]|$) ]] && return 0
  return 1
}

# The sentence addresses the requester or the conversation that produced the
# text. Exactly two followers stand the shape down: an anaphoric adverb ("as we
# discussed above / earlier"), and `in` in front of a document locator ("as we
# decided in §3 / in the ADR"). A bare `in` used to exempt the whole sentence,
# which correctly spared "as we decided in the ADR" but also spared "as we
# decided in favor of X" and "as we discussed in yesterday's meeting" — both
# residue, because the referent is the conversation, not a document.
# The actor-less passive ("As requested, retry three times") is the same shape
# without the pronoun, but it is matched only as a clause-final adverbial:
# bounded that way, the live attribution "as requested by the client" and the
# ordinary verb phrase "was requested" stay out without a second pattern.
# Closing quotes are not clause breaks here on purpose — behind one the words
# are a quoted voice, not the page's own address to its reader.
# The pronoun admits a CONTRACTED auxiliary ("as we've discussed", "as you'd
# requested"): the same actor and the same shape, so requiring a literal space
# after the pronoun let the contraction escape silently. Only `'ve` and `'d`
# are admitted, because the follower is a past participle and those are the
# only auxiliaries that can precede one — `'re`/`'ll`/`'m` would add nothing
# but ungrammatical alternatives, and admitting `'re` would newly match the
# present-tense passive "do it as you're asked", which addresses the reader
# generically rather than pointing at a prior exchange. Both apostrophe forms
# are spelled as literal ALTERNATIVES rather than a bracket class: `’` (U+2019)
# is multibyte, and a bracket class over it breaks under a C locale, where the
# regex is byte-based. Same reasoning, and same spelling, as the I6_ERE in
# plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.sh.
audit_noise_line_has_conversational_antecedent() {
  local line="$1" rest follower
  [[ "$line" =~ [Pp]er[[:space:]]+your[[:space:]]+request ]] && return 0
  [[ "$line" =~ [Pp]er[[:space:]]+our[[:space:]]+(conversation|discussion|chat) ]] && return 0
  [[ "$line" =~ [Ll]ike[[:space:]]+you[[:space:]]+said ]] && return 0
  [[ "$line" =~ (^|[^A-Za-z])[Aa]s[[:space:]]+requested[[:space:]]*([,;:.!?]|\)|$) ]] && return 0
  if [[ "$line" =~ [Aa]s[[:space:]]+(you|we)(\'ve|\'d|’ve|’d)?[[:space:]]+(asked|requested|discussed|agreed|decided)(.*)$ ]]; then
    rest="${BASH_REMATCH[4]}"
    # A follower counts only as a whole word behind whitespace, so punctuation
    # ("as you asked, …") leaves the antecedent flagged.
    if [[ "$rest" =~ ^[[:space:]]+([A-Za-z]+)(.*)$ ]]; then
      follower="${BASH_REMATCH[1],,}"
      rest="${BASH_REMATCH[2]}"
      case "$follower" in
      above | below | earlier | later | previously | elsewhere | under | at | on) return 1 ;;
      in) audit_noise_follower_is_document_locator "$rest" && return 1 ;;
      *) ;;
      esac
    fi
    return 0
  fi
  return 1
}

# The prose points at the work plan / changeset that produced the page rather
# than at the page's subject. Four of the code lib's cues are deliberately NOT
# carried over, each because a corpus sweep showed it matching live prose:
#   "per the plan"  — prefix-matches "per the planning chapter", and a doc
#                     citing a plan artifact that still exists is a live
#                     cross-reference, not residue;
#   "as planned"    — substring of "was planned", so "what was planned, what
#                     was done instead" self-matched;
#   "in this change" / "in this session" — ordinary domain vocabulary in an
#                     agent-tooling corpus.
# "in this PR" survives only with a first-person actor behind it, which is what
# separates narration ("in this PR we switch the default") from a live referent
# ("the files changed in this PR"). A CONTRACTED actor is still that actor, so
# the pronoun admits one ("in this PR we've already switched the default"):
# requiring a literal space after it let the same shape escape on a
# contraction, and widening to the contraction adds no false-positive surface
# because the discriminator is the pronoun, not the verb behind it. Unlike the
# antecedent above — whose past-participle follower admits only `'ve`/`'d` —
# any auxiliary can lead the present/future narration here, so all five are
# admitted; the non-words the shared alternation also spells (`I're`, `we'm`)
# cost nothing and keep this one group instead of two per-pronoun ones. Both
# apostrophe forms are literal alternatives, never a bracket class, for the
# C-locale reason recorded above.
audit_noise_line_has_plan_reference() {
  local line="$1"
  [[ "$line" =~ [Rr]eplaces[[:space:]]+the[[:space:]]+old ]] && return 0
  [[ "$line" =~ [Ii]n[[:space:]]+this[[:space:]]+(PR|MR|pull[[:space:]]+request|commit|changeset|refactor),?[[:space:]]+(we|I)(\'ve|\'re|\'ll|\'d|\'m|’ve|’re|’ll|’d|’m)?[[:space:]] ]] && return 0
  [[ "$line" =~ ([Tt]ask|[Pp]hase|[Ss]tep)[[:space:]]+#?[0-9]+[[:space:]]+(of|in)[[:space:]]+(the|this)[[:space:]]+plan ]] && return 0
  return 1
}

# Markdown restatement of the code skill's sanctioned-marker carve-out. Both
# forms denote OUTSTANDING TRACKED WORK, where the reference is the actionable
# part of the sentence; everything else is bare provenance, which is the shape.
# Nothing further earns a carve-out here: the sanctioned home for a provenance
# citation is a `## Sources` / `## History` footer, and the section exemptions
# in detect.sh already skip those (as they skip CHANGELOG.md, fences, and
# frontmatter) before any shape runs.
audit_noise_line_is_tracked_work() {
  local line="$1"
  # Task-list checklist item: `- [ ] … #123` / `- [x] … #123`.
  [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+\[[[:space:]xX]\][[:space:]] ]] && return 0
  # Tracked-work marker with a parenthesised reference.
  [[ "$line" =~ (TODO|FIXME|HACK|XXX)[[:space:]]*\(#?[A-Za-z0-9_-]+\) ]] && return 0
  return 1
}

# Bare provenance: a tracker, PR, or branch back-reference offered as the
# reason the surrounding prose says what it says.
audit_noise_line_has_ticket_pr_residue() {
  local line="$1"
  audit_noise_line_is_tracked_work "$line" && return 1
  [[ "$line" =~ [Ss]ee[[:space:]]+(PR|MR|pull[[:space:]]+request|issue|ticket)[[:space:]]*#?[0-9] ]] && return 0
  [[ "$line" =~ [Ss]ee[[:space:]]+the[[:space:]]+(PR|MR|pull[[:space:]]+request|issue|ticket)[[:space:]]*#?[0-9] ]] && return 0
  [[ "$line" =~ ([Ii]ntroduced|[Aa]dded|[Ll]anded|[Ss]hipped|[Ff]ixed|[Rr]everted|[Dd]ecided|[Aa]greed)[[:space:]]+in[[:space:]]+(PR|MR|issue|ticket)[[:space:]]*#?[0-9] ]] && return 0
  [[ "$line" =~ [Tt]racked[[:space:]]+in[[:space:]]+#[0-9] ]] && return 0
  [[ "$line" =~ ([Tt]racked|[Ff]iled|[Ll]ogged|[Rr]eported)[[:space:]]+(in|as|under)[[:space:]]+[A-Z][A-Z0-9]+-[0-9] ]] && return 0
  [[ "$line" =~ [Ff]rom[[:space:]]+the[[:space:]]+feature[[:space:]]+branch ]] && return 0
  return 1
}

# Append matching shape names into the nameref array (avoids a per-line
# command-substitution subshell in the detect hot loop).
#
# RESERVED OUT-NAMES: pass an out-array named anything but `line`, `unwrapped`
# or `stripped`. Bash binds a nameref to the nearest declaration in dynamic
# scope, so an out-variable sharing a name with one of this function's locals
# is shadowed by it and the caller silently receives nothing. No in-tree caller
# does this; the constraint is recorded because the failure is silent.
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
  if audit_noise_line_has_plan_reference "$stripped"; then
    _audit_noise_shapes_out+=('plan-reference')
  fi
  if audit_noise_line_has_conversational_antecedent "$stripped"; then
    _audit_noise_shapes_out+=('conversational-antecedent')
  fi
  if audit_noise_line_has_ticket_pr_residue "$stripped"; then
    _audit_noise_shapes_out+=('ticket-pr-residue')
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
  ghost-ref | preamble | negation-without-positive | ticket-pr-residue) printf '2' ;;
  citation | enum-list | scope-meta | plan-reference | conversational-antecedent) printf '1' ;;
  *) printf '3' ;;
  esac
}

# Set nameref to the tier digit without a subshell.
audit_noise_shape_tier_into() {
  local shape="$1"
  local -n _audit_noise_tier_out="$2"
  case "$shape" in
  ghost-ref | preamble | negation-without-positive | ticket-pr-residue) _audit_noise_tier_out=2 ;;
  citation | enum-list | scope-meta | plan-reference | conversational-antecedent) _audit_noise_tier_out=1 ;;
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
