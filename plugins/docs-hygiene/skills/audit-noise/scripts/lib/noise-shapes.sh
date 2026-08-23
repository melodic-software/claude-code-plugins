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
  # Recheck after the clause cut: an inline-code locator the strip removed
  # leaves only the punctuation that followed it (`on `path`, …` → `, …` →
  # empty). Empty-before-cut already counts as a locator; empty-after-cut is
  # the same signal and must not fall through to a "not a locator" miss.
  [[ -z "${head//[[:space:]]/}" ]] && return 0
  # A markdown link, a section sign, or a path is a locus outright. `#` counts
  # only ahead of a letter: `#anchor` is an anchor, `#482` is a tracker ref.
  [[ "$head" == '['* || "$head" == *'§'* || "$head" == '#'[a-z]* ]] && return 0
  [[ "${head%% *}" == */* ]] && return 0
  [[ "$head" =~ (^|[^a-z])(section|sections|chapter|chapters|appendix|step|steps|table|tables|figure|paragraph|adr|adrs|rfc|rfcs|spec|specs|specification|readme|changelog|convention|conventions|guide|schema|doc|docs|document|documentation)([^a-z]|$) ]] && return 0
  return 1
}

# The sentence addresses the requester or the conversation that produced the
# text. Exactly two follower classes stand the shape down: an anaphoric adverb
# ("as we discussed above / earlier"), and a preposition (`in` / `under` / `at`
# / `on`) in front of a document locator ("as we decided in §3 / in the ADR /
# on the ADR's recommendation"). A bare `in` used to exempt the whole sentence,
# which correctly spared "as we decided in the ADR" but also spared "as we
# decided in favor of X" and "as we discussed in yesterday's meeting" — both
# residue, because the referent is the conversation, not a document. `under`,
# `at`, and `on` carried the same blanket exemption until the locator predicate
# was applied to them too: "as we agreed on Tuesday" is residue, identically.
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
      above | below | earlier | later | previously | elsewhere) return 1 ;;
      in | under | at | on) audit_noise_follower_is_document_locator "$rest" && return 1 ;;
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
  if audit_noise_line_has_plan_reference "$stripped"; then
    _audit_noise_shapes_out+=('plan-reference')
  fi
  if audit_noise_line_has_conversational_antecedent "$stripped"; then
    _audit_noise_shapes_out+=('conversational-antecedent')
  fi
  if audit_noise_line_has_ticket_pr_residue "$stripped"; then
    _audit_noise_shapes_out+=('ticket-pr-residue')
  fi
  # Negation scans the UNWRAPPED form, not the strip: a hard-guardrail marker is
  # routinely the inline-code span itself (`--force`, `rm -rf`), and stripping it
  # would erase the very evidence the carve-out needs — turning a guardrail into
  # a false finding rather than a withheld one.
  if audit_noise_line_has_negation_without_positive "$unwrapped"; then
    _audit_noise_shapes_out+=('negation')
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
  ghost-ref | preamble | ticket-pr-residue | negation) printf '2' ;;
  citation | enum-list | scope-meta | plan-reference | conversational-antecedent) printf '1' ;;
  *) printf '3' ;;
  esac
}

# Set nameref to the tier digit without a subshell.
audit_noise_shape_tier_into() {
  local shape="$1"
  local -n _audit_noise_tier_out="$2"
  case "$shape" in
  ghost-ref | preamble | ticket-pr-residue | negation) _audit_noise_tier_out=2 ;;
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

# --- negation-without-positive (shape: negation) ----------------------------
# A prohibition with no positive alternative stated in the same sentence. The
# write-side doctrine this audits is docs-hygiene:write-for-agents "Prompt the
# positive"; this is its audit-side completion.
#
# BOTH WITHHOLDING BOUNDARIES REQUIRE POSITIVE EVIDENCE ON THE SENTENCE, so an
# unresolved candidate falls through to the emitting rule. That direction is the
# detector-findings crosswalk's admission test 2 (fail-safe toward EMITTING),
# and it is checked on each boundary rather than only the one easier to argue:
#   1. a paired positive alternative -> paired, nothing to remediate
#   2. a hard guardrail whose constraint a positive form cannot carry
# Neither present -> emit. Widening either list withholds more, which is the
# direction that silently loses findings.
#
# The carve-out lives HERE, in the shared scanner, so the human report and the
# relay file receive one disposition for one candidate — the contract's
# "fall-through takes effect before the producer's FIRST output".

# Split into sentences on [.!?] followed by whitespace.
#
# Peeled RIGHT-TO-LEFT with a greedy leading `.*`, which is what makes an
# embedded abbreviation safe. A left-anchored `^[^.!?]*[.!?]+[[:space:]]+`
# cannot skip past `e.g.` — that period is followed by `g`, not whitespace, so
# the anchored match fails on the FIRST iteration and the whole line collapses
# into one "sentence". That is not a cosmetic difference: on
# `See e.g. the credential rotation policy. Never call the tool directly.` the
# guardrail word in the first clause would then suppress the real prohibition in
# the second, SILENTLY WITHHOLDING a finding — the one outcome the carve-outs
# are built to make impossible.
#
# Peeling from the right instead splits at every terminator that IS followed by
# whitespace, so an abbreviation merely over-splits (`See e.g.` becomes its own
# fragment). Over-splitting only narrows the window a suppressing marker can act
# from, which is the fail-safe direction.
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

# All three predicates match against a LOWERCASED sentence so each pattern can
# spell whole words. Writing them with a leading either-case character class
# instead would leave a truncated word after the class, and the repo's typos
# linter reads that remainder as a misspelling and FAILs the file.
#
# EVERY alternative is fenced by non-alphanumeric boundaries. Bare substrings
# collide with longer words, and on the two WITHHOLDING predicates that
# collision is silent finding loss — the exact direction this rule set is built
# to avoid: `secretary` contains `secret` (guardrail) and `preferentially`
# contains `prefer` (pairing), so an unfenced pattern withholds ordinary prose.
# The boundary is spelled out rather than using `\b`, which is a GNU-grep
# extension and not portable ERE.
AUDIT_NOISE_APOS="['’]"

# The contraction wildcard has to be an apostrophe CLASS, never `.`: `don.t`
# matches `donut`, so ordinary prose was emitted as a Tier 2 finding.
audit_noise_sentence_has_prohibition() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(never|do[[:space:]]+not|don${AUDIT_NOISE_APOS}t|avoid|must[[:space:]]+not|should[[:space:]]+not|shouldn${AUDIT_NOISE_APOS}t)([^[:alnum:]]|$) ]]
}

# Evidence that the positive alternative is already paired in this sentence.
# Inflections of `prefer` are enumerated so the verb still matches while
# `preferentially` / `preference` do not.
audit_noise_sentence_has_positive_pairing() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(instead|rather[[:space:]]+than|prefer(s|red|ring)?|in[[:space:]]+place[[:space:]]+of|in[[:space:]]+favou?r[[:space:]]+of)([^[:alnum:]]|$) ]]
}

# Hard guardrails a positive form cannot carry: the prohibition IS the correct
# shape. Kept deliberately TIGHT to safety-critical markers — a generic verb
# ("delete", "merge", "force") would withhold ordinary prose and turn a
# fail-safe-toward-emitting rule into a silent one. `vulnerab` stays stemmed on
# purpose (vulnerable / vulnerability); the stem is bounded on the left so it
# cannot match inside a longer unrelated word.
audit_noise_sentence_has_hard_guardrail() {
  local s="${1,,}"
  [[ "$s" =~ (^|[^[:alnum:]])(secrets?|credentials?|tokens?|passwords?|api[[:space:]]+keys?|force-push(es|ed|ing)?|force[[:space:]]+push(es|ed|ing)?|--force|rm[[:space:]]+-rf|destructive|irreversible|data[[:space:]]+loss|production|security|vulnerab[a-z]*|rewrite[[:space:]]+history)([^[:alnum:]]|$) ]]
}

# A before -> after demonstration is a worked example (protected content), not
# an instruction carrying the defect.
audit_noise_sentence_is_worked_example() {
  [[ "$1" == *'→'* || "$1" == *'->'* ]]
}

# --- Scope narrowings: what SELECTS at all ----------------------------------
# Measured, not argued. Without these two tests the shape fired 1053 times on an
# 85-file sample of this repo (12.4 per file, 99% of all findings); with them,
# 31. The rule is only usable inside this scope.
#
# 1. IMPERATIVE ONLY — the cue must be line-initial, after list, blockquote and
#    emphasis markers. "Prompt the positive" is a rule about INSTRUCTIONS, so a
#    descriptive negation ("Older versions do not support this flag", "the
#    config never loads") is not in its scope at all and must not select. A
#    mid-sentence prohibition is excluded by construction, and that is correct:
#    correctly paired prose puts the cue AFTER its positive ("Prefer X; never
#    Y"), so a line-initial test already declines what is already compliant.
# 2. THE LINE MUST END ITS SENTENCE — this repo hard-wraps prose, and the
#    pairing rule is per SENTENCE, so a continuation line cannot be shown to
#    lack a positive that sits on the next line. The same test excludes a table
#    row, which ends in `|`.
#
# Both narrowings are due to #3180, which established them against a 1140-file
# corpus sweep; this is that work adopted after #3194 shipped the wider form.

# Strip list, blockquote, task-list-checkbox and leading emphasis markers so a
# cue that opens the content still reads as initial. Ordered items are accepted
# with either delimiter (`1.` and `1)`), and a task-list checkbox is stripped
# after its bullet so `- [ ] Never …` reaches the cue test — both are ordinary
# ways this repo writes a directive, and missing them would withhold silently.
# `>` and `)` are written unescaped inside their bracket expressions: a
# backslash-escaped `\>` is a GNU word-boundary operator elsewhere in the
# toolchain, and the repo's portability lint rejects the form on sight.
audit_noise_strip_line_lead() {
  local s="$1"
  local -n _audit_noise_lead_out="$2"
  # Held in a variable: an unquoted `>` inside [[ =~ ]] reads as a redirection
  # to the parser, and quoting the pattern inline would make it a literal.
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

# True when the cue opens THIS SENTENCE — an imperative prohibition rather than
# a descriptive one.
#
# Applied per SENTENCE, not once per physical line. A line-level test admits the
# whole line on its first sentence and then lets the loop flag a later
# descriptive one: `Do not use markdown; instead use HTML. Older versions do not
# support SVG.` opens imperatively, but its second sentence is exactly the
# out-of-scope prose the gate exists to exclude. Testing each candidate keeps
# the gate's meaning ("is this an instruction?") attached to the text actually
# being reported.
audit_noise_sentence_opens_with_prohibition() {
  local lead=""
  audit_noise_strip_line_lead "$1" lead
  local s="${lead,,}"
  [[ "$s" =~ ^(never|do[[:space:]]+not|don${AUDIT_NOISE_APOS}t|avoid|must[[:space:]]+not|should[[:space:]]+not|shouldn${AUDIT_NOISE_APOS}t)([^[:alnum:]]|$) ]]
}

# True when the line closes its sentence, allowing a trailing emphasis run.
# A hard-wrapped continuation and a table row (ending `|`) both fail this.
audit_noise_line_ends_sentence() {
  local s="$1"
  s="${s%"${s##*[![:space:]]}"}"
  [[ "$s" =~ [.!?](\*\*\*|\*\*|\*|___|__|_|\)|\"|\'|’)*$ ]]
}

# Which prohibition fired, in the run's own values. Reported from the sentence
# that ACTUALLY triggered: a line whose first sentence is carved out
# ("Never commit a secret. Do not use markdown.") would otherwise report the
# carved-out marker and point review at the guardrail rather than the finding.
AUDIT_NOISE_FIRED_MARKER=""

audit_noise_line_has_negation_without_positive() {
  local sentences=() s lower m
  AUDIT_NOISE_FIRED_MARKER=""
  # Line-level gate first — cheapest, and genuinely a property of the LINE: a
  # continuation cannot be shown to lack a positive sitting on the next one.
  audit_noise_line_ends_sentence "$1" || return 1
  audit_noise_split_sentences_into sentences "$1"
  for s in "${sentences[@]}"; do
    # The imperative gate is per SENTENCE, so a line that opens imperatively
    # cannot carry a later descriptive sentence into a finding.
    audit_noise_sentence_opens_with_prohibition "$s" || continue
    audit_noise_sentence_has_prohibition "$s" || continue
    audit_noise_sentence_has_positive_pairing "$s" && continue
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
