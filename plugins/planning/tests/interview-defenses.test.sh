#!/usr/bin/env bash
# Regression gate for the two BEHAVIORAL defenses that license `planning:interview`'s
# synthesize-directly paths (issue #2997, from the course lane 4 audit in
# docs/upstream/aihero-course.md "Lane 4: plan mode / asset rush"):
#
#   Case A — STOP-on-gap. `lock` skips Q&A, so the only thing standing between it and a
#            Brief that fudges an unknown is the rule that a gap surfacing mid-synthesis
#            HALTS the run.
#   Case B — the auto-guard. `auto`'s synthesize-directly path may close facts and
#            unambiguous conventional defaults ONLY; a decision genuinely the user's is
#            asked, or — unattended, and only on the CALLER's declaration — recorded
#            `blocked` with arbiter USER-RESERVED. It is never captured as an assumption.
#
# The lane-4 audit graded both defenses as holding. They are prose rules with no runner
# behind them: the marketplace has no model-graded eval runner (docs/MIGRATION-PLAYBOOK.md,
# "Method source" — grading is a human judgment pass until the deferred runner lands), so
# the eval cases in skills/interview/evals/evals.json are a rubric, not a gate. This suite
# is the gate: it pins the eval cases that grade each defense AND the load-bearing rule text
# in the skill body those cases grade against, so a prose edit that weakens either defense —
# or a case edit that stops grading it — fails here instead of passing review as a wording
# change.
#
# It is a contract tripwire, not a semantic proof, and it gates in three layers because
# each outer layer catches an attack the inner one is blind to. Every layer was added after
# a fresh-context verifier demonstrated the shape it closes.
#
#   1. Phrase pins (`pin`, `pin_once`, `within`) anchor on a phrase carrying the rule's
#      MEANING — the halt, the prohibition, the arbiter tag — never on incidental wording,
#      and several are structural (the rule must sit inside the step that owns it). They
#      catch DELETION and REWORDING, and they are the layer that names WHICH clause went.
#
#   2. Whole-line pins (`pin_exact`) hold a byte-exact copy of the eleven lines that state
#      the two rules outright. Those are not the only defense lines the suite pins —
#      supporting ones (the in-round no-silent-resolve rule, the register bindings) carry a
#      phrase pin instead and are covered by layer 3 through the section they sit in,
#      never by a byte-exact copy of their own. Phrase
#      pins are blind to a clause NEUTRALIZED IN PLACE: appending "**Exception:** … the
#      guard is satisfied by recording the residue under `### Captured assumptions`" to the
#      auto-guard, or "a gap counts as real only when it blocks writing the Brief at all"
#      to the `lock` routing line, inverts both defenses while leaving every pinned phrase
#      intact. Whole-line equality catches any SAME-LINE edit.
#
#   3. Digests (`pin_section`, `pin_case_digest`, `pin_case_set`, `pin_file`,
#      `pin_frontmatter`) hash whole regions. Whole-line pins are blind to anything ADDED
#      BESIDE a pinned line rather than to it. FOURTEEN such shapes were demonstrated against
#      earlier revisions of this suite, each passing at FAIL=0:
#        - a new adjacent paragraph inside Step 1.5 ("**Applying the two rules above.** In
#          practice a gap counts as \"real\" only when …");
#        - the same, four lines below the router row inside the Action Router section;
#        - a criterion ADDED to an eval case contradicting one already pinned ("Recording
#          the residue under `### Captured assumptions` … is an equally acceptable
#          outcome");
#        - a rewritten fixture, so case A's planted gap IS answered by the codebase and
#          the case grades nothing;
#        - a SIBLING eval case ADDED, saying the captured assumption is preferred, leaving
#          15 and 16 byte-identical;
#        - an existing sibling REWRITTEN in place to say the same, keeping its name and so
#          the roster hash too;
#        - a crafted heading that MOVED a digested region's own boundary, so an override
#          appended after it fell outside the hash (see `section_digest`);
#        - the adjacent paragraph shifted one line UP, to the end of Step 1, where it reads
#          as the preamble governing both rules below it;
#        - a qualifier added to the frontmatter `description`, the always-loaded routing
#          surface a reader meets before any section;
#        - a qualifier added to a DIFFERENT frontmatter key (`metadata.summary`), short
#          enough to clear the cheatsheet's length cap, which pinning `description` alone
#          did not reach;
#        - an in-place rewrite of a NON-pinned sibling case that nonetheless rests on the
#          same fact-vs-decision line (case 8, `facts-looked-up-decisions-asked`);
#        - an append-only inversion of a defense line carrying only a PHRASE pin, in an
#          undigested section — the in-round no-silent-resolve rule in Stance, and the
#          register-binding lines in loop.md's register section;
#        - a governing preamble in the `## The interview loop` intro, three lines above the
#          digested Step 1 region;
#        - an append-only inversion of loop.md's TWIN of a byte-pinned SKILL.md line — the
#          confirmation-gate exemption in its Step 3, and the `USER-RESERVED` arbiter
#          guidance in its Step 4 — leaving the pinned original standing.
#      Digests cover thirteen sections, the whole YAML frontmatter, the eight cases that speak
#      to these rules, the case roster, and the four fixtures. Inside those regions, an
#      insertion, deletion, or reordering fails. EVERY line this suite phrase-pins as a
#      defense, and every loop.md TWIN of a byte-pinned SKILL.md line, now sits inside a
#      digested region — that is the invariant to preserve when adding a pin: a phrase pin
#      whose line has no enclosing digest is append-invertible, and so is an unpinned twin.
#
# WHAT IS STILL NOT GATED, so nobody reads more into a green run than is there:
#   - Prose OUTSIDE the digested regions. Among them — not an exhaustive list — SKILL.md's
#     Purpose, Emit-checklist, Step 2, Step 5, session-config and composition sections, the
#     undigested parts of `context/loop.md`, `context/gotchas.md`,
#     `templates/checklist.md`, and the plugin README. The digested set covers the rules'
#     own homes, every line the suite phrase-pins, and every placement a weakening has
#     actually been demonstrated to reach for. It is not a proof about the whole corpus,
#     and the distance a qualifier needs is not large — one of the demonstrated escapes was
#     a single paragraph abutting a digest boundary.
#   - An in-place rewrite of an eval case in this file other than the eight digested ones.
#     Nothing here judges whether such a rewrite bears on these rules; the eight are the
#     ones read as bearing on them today, not a closed set.
#   - Anything semantic. This gate proves the RULE TEXT and the CASE INPUTS are intact. It
#     cannot prove the skill OBEYS them — only a model-graded runner could, and the
#     marketplace has none (docs/MIGRATION-PLAYBOOK.md, "Method source").
# Read this suite as raising the cost of a silent weakening, never as proving one
# impossible.
#
# Rewording, extending, or qualifying a pinned line is EXPECTED to fail, including a typo
# fix, and so is any edit inside a digested region. That is the contract for a load-bearing
# behavioral rule with no runner behind it: re-read the defense, confirm it still holds,
# then update the skill body and this suite in one change.
#
# Relationship to the older cases. evals.json ships three narrative cases over the same two
# defenses — `auto-guard-never-folds-user-choice` (2), `lock-mode-does-not-fudge-gap` (3),
# and `unattended-run-emits-named-blockers-not-assumptions` (13). They are kept, not
# superseded: they state each rule in the abstract with no fixtures, which is the cheap
# surface a reader scans. Cases 15 and 16 are the fixture-backed regression pair — a
# planted, genuinely-open decision and a resolved-but-one context. Coverage of the rules is
# deliberately doubled, and all five are digested — a sibling advertised as kept coverage
# that has been rewritten to say the opposite is worse than no sibling at all. Cases 1, 8,
# and 12 are digested for the same reason one step removed: they rest on the fact-vs-
# decision line the auto-guard draws, or on the no-silent-resolution rule, so a rewrite of
# one licenses the capture for any grader reading the file.
#
# shellcheck disable=SC2016  # single quotes are deliberate throughout: every pin_exact argument is
# a VERBATIM copy of a markdown line from the skill body, dense with backticks and inline code. Any
# expansion at all would corrupt the pin and silently weaken the gate it enforces.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/interview/SKILL.md"
LOOP="$PLUGIN_DIR/skills/interview/context/loop.md"
EVALS="$PLUGIN_DIR/skills/interview/evals/evals.json"
FIXTURES="$PLUGIN_DIR/skills/interview/evals/fixtures"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# jq is required, never optional: the eval-case half of every assertion below reads
# evals.json structurally. Skipping it would vacate the coverage this suite exists for.
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to grade $EVALS — this suite has no meaningful subset without it" >&2
  exit 1
fi

for f in "$SKILL" "$LOOP" "$EVALS"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing required file: $f" >&2
    exit 1
  fi
done

if ! jq -e . "$EVALS" >/dev/null 2>&1; then
  echo "FAIL: $EVALS is not parsable JSON" >&2
  exit 1
fi

# --- helpers ---------------------------------------------------------------

# pin <label> <file> <literal phrase>
# The phrase must appear at least once, matched literally (grep -F: the rules are full
# of backticks, asterisks, and slashes that a regex would mangle).
pin() {
  local label="$1" file="$2" phrase="$3"
  if grep -qF -- "$phrase" "$file"; then
    ok "$label"
  else
    fail "$label — phrase not found in ${file#"$PLUGIN_DIR/"}: \"$phrase\""
  fi
}

# pin_once <label> <file> <literal phrase>
# Exactly one occurrence: a duplicated rule is a second home that can drift.
pin_once() {
  local label="$1" file="$2" phrase="$3" count
  count="$(grep -cF -- "$phrase" "$file")"
  if [[ "$count" -eq 1 ]]; then
    ok "$label"
  else
    fail "$label — expected exactly 1 occurrence in ${file#"$PLUGIN_DIR/"}, got $count: \"$phrase\""
  fi
}

# pin_exact <label> <file> <full line>
# WHOLE-LINE equality (grep -Fxq). The phrase pins above catch a clause being DELETED or
# reworded; they cannot catch a clause being NEUTRALIZED IN PLACE — appending "Exception:
# … the guard is satisfied by recording the residue under `### Captured assumptions`" to
# the auto-guard leaves every pinned phrase intact and guts the defense. Whole-line
# equality closes that: any edit to a defense line, additive or otherwise, fails here.
#
# The cost is deliberate. A typo fix inside one of these lines fails this suite. That is
# the contract for a load-bearing behavioral rule with no runner behind it: the failure
# says re-read the defense, confirm it still holds, then update BOTH the skill body and
# the pinned copy below in the same change.
pin_exact() {
  local label="$1" file="$2" line="$3"
  if grep -Fxq -- "$line" "$file"; then
    ok "$label"
  else
    fail "$label — no line in ${file#"$PLUGIN_DIR/"} matches the pinned defense text EXACTLY. The rule was reworded, extended, or qualified. Re-read it, confirm the defense still holds, then update the pin. Pinned: $line"
  fi
}

# sha256 of stdin. GNU coreutils ships sha256sum; a BSD userland (macOS) ships
# `shasum -a 256` instead. Probe both — a missing digest tool would otherwise silently
# vacate every section and case pin below, which is the one failure mode this suite may
# never have.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    echo "NO-DIGEST-TOOL"
  fi
}

# section_digest <file> <open heading line> <close heading line>
# sha256 of everything strictly BETWEEN the two heading lines, each matched as a WHOLE
# LINE. Whole-line matching is load-bearing, not tidiness: a prefix match let a crafted
# heading MOVE the region's own boundary. Appending
# `### Step 2 — Drive the frontier-rounds loop, and how to read Step 1.5 before it` plus an
# override paragraph as the last thing inside Step 1.5 closed the region early under a
# prefix match, so the override fell outside the hash and the suite stayed green. Under
# whole-line matching that crafted heading is just another line inside the region, and the
# digest changes. `pin_section` additionally requires each boundary to occur EXACTLY ONCE,
# so a duplicated heading cannot truncate the region either.
#
# `close` is a builtin in mawk (and `open` reads badly beside it), so the awk variables are
# named h_open / h_close — assigning to a builtin name is a run-time error, not a warning,
# and mawk is the default awk on Debian-family runners.
section_digest() {
  awk -v h_open="$2" -v h_close="$3" '
    $0 == h_open { inside = 1; next }
    $0 == h_close { inside = 0 }
    inside { print }
  ' "$1" | sha256_stdin
}

# pin_section <label> <file> <open heading> <close heading> <expected sha256>
# WHOLE-SECTION digest. `pin_exact` closes the same-line neutralize-in-place edit; it is
# blind to the SAME override delivered one line lower, as a new adjacent paragraph inside
# the section that owns the rule ("**Applying the two rules above.** In practice a gap
# counts as \"real\" only when …"). Every pinned line stays byte-identical and both
# defenses invert. Digesting the whole section closes that: an insertion, deletion, or
# reordering inside the rule's home fails, provided the region's own boundaries hold —
# which is why both boundaries are matched whole-line and required to be unique.
#
# The failure is deliberately opaque about WHAT changed — `git diff` shows that. What it
# must convey is the obligation: re-read the section, confirm neither defense was weakened
# or qualified by the new text, then update the digest in the same change.
pin_section() {
  local label="$1" file="$2" open="$3" close="$4" want="$5" got n_open n_close
  n_open="$(grep -Fxc -- "$open" "$file" || true)"
  n_close="$(grep -Fxc -- "$close" "$file" || true)"
  if [[ "$n_open" != "1" || "$n_close" != "1" ]]; then
    fail "$label — the section boundaries are no longer unique whole lines in ${file#"$PLUGIN_DIR/"} (\"$open\" x$n_open, \"$close\" x$n_close). A duplicated or renamed boundary moves the digested region, which is how a region pin gets silently emptied. Restore the headings, or re-anchor the pin and update the digest."
    return
  fi
  got="$(section_digest "$file" "$open" "$close")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the section pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the section between \"$open\" and \"$close\" in ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). Anything added inside this section can qualify the defense it houses WITHOUT touching a pinned line. Re-read the section, confirm neither defense was weakened, then update the digest."
  fi
}

# pin_frontmatter <label> <file> <expected sha256>
# Digest of the WHOLE YAML frontmatter block — everything between the opening `---` on
# line 1 and the closing `---`. The frontmatter is inside no section, so no `pin_section`
# reaches it, and it is the always-loaded surface a reader meets before any step. Pinning
# only `description:` was not enough: a 70-codepoint `metadata.summary` reading "a
# defensible residue is captured, never halted on" inverts both rules, stays under the
# cheatsheet's length cap, and no other repo gate rejects it. The whole block is pinned so
# every key is covered, present and future.
pin_frontmatter() {
  local label="$1" file="$2" want="$3" got
  got="$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$file" | sha256_stdin)"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the frontmatter pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the YAML frontmatter of ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). Frontmatter is loaded before any section, so a qualifier in ANY key here reaches every invocation. Re-read it, confirm neither defense was weakened, then update the digest."
  fi
}

# pin_case_digest <label> <case name> <expected sha256>
# WHOLE-CASE digest over the eval case's normalized JSON. `graded_mention` proves a
# criterion is still PRESENT; it cannot see a criterion ADDED that contradicts it
# ("Recording the residue under `### Captured assumptions` at its recommended value is an
# equally acceptable outcome"), which neutralizes the case while every pinned substring
# survives. Digesting the whole case object closes that.
pin_case_digest() {
  local label="$1" name="$2" want="$3" got
  got="$(jq -S -c --arg n "$name" '.evals[] | select(.name == $n)' "$EVALS" | sha256_stdin)"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the case pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — eval case \"$name\" changed (want $want, got $got). A criterion may have been added that contradicts one already pinned. Re-read the case, confirm it still rejects the silent capture, then update the digest."
  fi
}

# pin_file <label> <file> <expected sha256>
# WHOLE-FILE digest, used for the fixtures. A case's discriminating power lives in its
# plant: rewriting `lock-stop-on-gap/codebase-survey.md` so the planted gap IS answered by
# the codebase leaves the case syntactically intact and grading nothing. The fixtures are
# the case's input; they are pinned like the case itself.
pin_file() {
  local label="$1" file="$2" want="$3" got
  got="$(sha256_stdin <"$file")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the fixture pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). This fixture IS the case's plant: if it no longer plants a genuinely-open decision (case A) or a resolved-but-one context (case B), the case grades nothing. Re-read it, confirm the plant survives, then update the digest."
  fi
}

# pin_case_set <label> <expected sha256 of the id:name roster>
# The two pinned cases can also be neutralized from OUTSIDE themselves: a sibling case added
# to the same file, saying capturing the assumption is preferred, leaves 15 and 16
# byte-identical while contradicting them for any grader reading the set. Pinning the whole
# roster makes ADDING, removing, or renumbering any case in this file a deliberate act that
# re-confirms the two defenses first. A sibling REWRITTEN in place keeps the roster hash
# identical, so the three siblings that speak to these same rules are digested separately
# below.
pin_case_set() {
  local label="$1" want="$2" got
  got="$(jq -r '.evals[] | "\(.id):\(.name)"' "$EVALS" | sort | sha256_stdin)"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the roster pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the eval-case roster in ${EVALS#"$PLUGIN_DIR/"} changed (want $want, got $got). Adding a case is fine; adding one that contradicts case 15 or 16 is not. Confirm no new case licenses the silent capture or a fudged gap, then update the digest with: jq -r '.evals[] | \"\\(.id):\\(.name)\"' <evals.json> | sort | sha256sum"
  fi
}

# line_of <file> <literal phrase>  -> first matching line number, or empty
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# within <label> <file> <phrase> <open heading> <close heading>
# Structural: the rule must live between two headings, so it cannot be relocated out of
# the step that owns it while still greping green.
within() {
  local label="$1" file="$2" phrase="$3" open="$4" close="$5"
  local p o c
  p="$(line_of "$file" "$phrase")"
  o="$(line_of "$file" "$open")"
  c="$(line_of "$file" "$close")"
  if [[ -n "$p" && -n "$o" && -n "$c" && "$p" -gt "$o" && "$p" -lt "$c" ]]; then
    ok "$label (line $p, between $o and $c)"
  else
    fail "$label — expected \"$phrase\" between \"$open\" and \"$close\" in ${file#"$PLUGIN_DIR/"} (phrase=$p open=$o close=$c)"
  fi
}

# case_json <case name>  -> the eval case object, or empty
case_json() {
  jq -c --arg n "$1" '.evals[] | select(.name == $n)' "$EVALS"
}

# graded_mention <label> <case json> <literal substring>
# The case must still GRADE the thing it was written to grade, and grade it as a CHECKABLE
# item: the phrase must appear in the `expectations` ARRAY, not merely in the
# `expected_output` rubric prose. A defense described in the prose but dropped from the
# graded list is a case that reads right and grades nothing. Substring match,
# case-sensitive where the rule's own casing is load-bearing (HALTS, USER-RESERVED,
# ATTENDED, DISTINCT).
graded_mention() {
  local label="$1" json="$2" needle="$3" text
  text="$(printf '%s' "$json" | jq -r '(.expectations // []) | join(" ")')"
  case "$text" in
  *"$needle"*) ok "$label" ;;
  *) fail "$label — no graded expectation mentions: \"$needle\"" ;;
  esac
}

# --- shared: the two cases exist, are addressable, and ship their fixtures --

CASE_A_NAME="lock-halts-on-planted-open-decision"
CASE_B_NAME="auto-residue-asked-or-user-reserved-never-assumed"

CASE_A="$(case_json "$CASE_A_NAME")"
CASE_B="$(case_json "$CASE_B_NAME")"

for pair in "A:$CASE_A_NAME:$CASE_A" "B:$CASE_B_NAME:$CASE_B"; do
  arm="${pair%%:*}"
  rest="${pair#*:}"
  name="${rest%%:*}"
  json="${rest#*:}"
  if [[ -n "$json" ]]; then
    ok "case $arm present in evals.json: $name"
  else
    fail "case $arm missing from evals.json: expected an eval case named $name"
  fi
done

# Fixture reachability: a planted-decision case whose plant is gone grades nothing.
for fx in \
  "lock-stop-on-gap/task-context.md" \
  "lock-stop-on-gap/codebase-survey.md" \
  "auto-guard-residue/task-context.md" \
  "auto-guard-residue/codebase-survey.md"; do
  if [[ -f "$FIXTURES/$fx" ]]; then
    ok "fixture present: evals/fixtures/$fx"
  else
    fail "missing fixture: evals/fixtures/$fx"
  fi
done

# Each case must DECLARE its fixtures, not merely name them in prose — a `files: []` case
# with prose paths is the dodge the eval-quality lint's Q4 check exists to surface.
if [[ -n "$CASE_A" ]]; then
  declared="$(printf '%s' "$CASE_A" | jq -r '(.files // []) | length')"
  if [[ "$declared" -eq 2 ]]; then
    ok "case A declares both fixtures in files[]"
  else
    fail "case A declares $declared fixture(s) in files[]; expected 2"
  fi
fi
if [[ -n "$CASE_B" ]]; then
  declared="$(printf '%s' "$CASE_B" | jq -r '(.files // []) | length')"
  if [[ "$declared" -eq 2 ]]; then
    ok "case B declares both fixtures in files[]"
  else
    fail "case B declares $declared fixture(s) in files[]; expected 2"
  fi
fi

# --- whole-section and whole-case digests (the outermost layer) ------------
#
# Update procedure when one of these fires: read `git diff` for the named section or case,
# confirm in words that neither defense was weakened, qualified, or contradicted by the
# change, then recompute and replace the digest below IN THE SAME COMMIT.
#
# The boundary tests below MUST match `section_digest`'s — whole-line equality, not a
# prefix match. They agree on today's content and diverge in exactly the crafted-heading
# scenario the pin defends against, so a prefix-matching recompute would produce a value
# the function never yields.
#
#   frontmatter: awk 'NR==1 && $0=="---"{i=1;next} i && $0=="---"{exit} i{print}' <file> | sha256sum
#   section:     awk -v h_open='<open>' -v h_close='<close>' \
#                  '$0==h_open{i=1;next} $0==h_close{i=0} i{print}' <file> | sha256sum
#   case:        jq -S -c '.evals[] | select(.name == "<name>")' <evals.json> | sha256sum
#   roster:      jq -r '.evals[] | "\(.id):\(.name)"' <evals.json> | sort | sha256sum
#   fixture:     sha256sum <fixture>
#
# On a BSD userland substitute `shasum -a 256` for `sha256sum`, as `sha256_stdin` does.

pin_frontmatter "SKILL.md frontmatter is unchanged (the always-loaded routing surface, every key)" \
  "$SKILL" \
  "50038bccdd8ad86fdb0fa50b73eedbbf25a53b506192310bedb1993eb1944e0c"

# The Stance section houses the partial-round rule ("NEVER silently resolve an unanswered
# question to its recommendation — the auto-guard applies inside rounds too"), and the
# register section houses the two lines binding a surfaced gap and an unattended blocker
# into the register. Both were phrase-pinned only, so an appended `**Exception:**` on
# either inverted it at FAIL=0. Their sections are digested, which covers the lines and any
# paragraph placed beside them.
pin_section "SKILL.md Stance section is unchanged (the in-round no-silent-resolve rule lives here)" \
  "$SKILL" \
  "## Stance: supportive, depth-first, opinionated" \
  "## The interview loop" \
  "31c51b271b230234aae7951f601c2ca61f0b318376450d7c92bdc1e645c7e93f"
pin_section "SKILL.md interview-loop preamble is unchanged (it governs every step below it)" \
  "$SKILL" \
  "## The interview loop" \
  "### Step 1 — Survey before you ask" \
  "c84a3506c3410b64938b898238a53f502e5e411522ea61e7444f3ad382a21860"
pin_section "loop.md open-question register section is unchanged (it binds gaps and blockers to the gate)" \
  "$LOOP" \
  "## The open-question register" \
  "## Step 3 — Recognize the stop condition" \
  "66dd3352d4ad6152aa6237b92f1cc1abc31f2cdd5ad5a517adb859408f52f26e"
# loop.md carries TWINS of two SKILL.md lines that are byte-pinned there: the
# confirmation-gate exemption ("`lock` is exempt … its STOP-on-gap rule still applies") in
# Step 3, and the `USER-RESERVED` arbiter guidance in Step 4. A twin with no pin is a
# second home that can be inverted while the pinned original stands.
pin_section "loop.md Step 3 section is unchanged (it twins the confirmation-gate exemption)" \
  "$LOOP" \
  "## Step 3 — Recognize the stop condition" \
  "## Step 4 — Section guidance for the Brief" \
  "28618c7e071f66a0db165c55e70a89cd7f88a85a28979cd1f6e66e2f7dc08822"
pin_section "loop.md Step 4 section is unchanged (it twins the USER-RESERVED arbiter guidance)" \
  "$LOOP" \
  "## Step 4 — Section guidance for the Brief" \
  "## Brief" \
  "5ffe0bdc0f4b221cb442279adbe9838369eba71f8d6c972e2360af569a7170c2"

pin_section "SKILL.md Step 1 section is unchanged (a preamble here reads as governing the two rules below)" \
  "$SKILL" \
  "### Step 1 — Survey before you ask" \
  "### Step 1.5 — Auto-detect (default action only)" \
  "1ccf5bdb01ec18254829b9bb4b5acad82dee1391b488fb4d6754bec495b762b5"
pin_section "SKILL.md Step 4 section is unchanged (the Brief's assumption machinery lives here)" \
  "$SKILL" \
  "### Step 4 — Persist the contract" \
  "### Step 5 — Hand off" \
  "1531fc732e4884b079f491fba339e1c2206c0ce440688b06a591fa0c447df438"
pin_section "SKILL.md Step 1.5 section is unchanged (auto-guard + unattended + \`lock\` routing live here)" \
  "$SKILL" \
  "### Step 1.5 — Auto-detect (default action only)" \
  "### Step 2 — Drive the frontier-rounds loop" \
  "f53c628234a41c475f406b8e5ff76607828b01279f1f03a631f1d10afaf7d9e0"
pin_section "loop.md Step 1.5 section is unchanged (loop's auto-guard + \`lock\` STOP line live here)" \
  "$LOOP" \
  "## Step 1.5 — Auto-detect: gap analysis without asking" \
  "## Step 2 — Drive the decision tree" \
  "ce60282043404a03645117d6cda4c6e8810165d541f20b34c4e06a77578d6b52"
pin_section "loop.md Unattended path section is unchanged (the ladder lives here)" \
  "$LOOP" \
  "### Unattended path" \
  "### Gate before locking" \
  "c538805b63397c4c802ea17b357c27312504bb951b5188c3b9a24d4c4824c778"

pin_case_digest "eval case A is unchanged (no criterion added that contradicts the halt)" \
  "$CASE_A_NAME" \
  "2f9db80a10e17b2c37e8623680755b5857fadefa87fdf8a0e54af1e145548c2e"
pin_section "SKILL.md Action Router section is unchanged (the \`lock\` row and its reading live here)" \
  "$SKILL" \
  "## Action Router" \
  "## Stance: supportive, depth-first, opinionated" \
  "ce60bb0a5417db42a4388c2cd8f3ca5c335d7dbcc22ae9a8e0b420dbddc81540"
pin_section "SKILL.md Step 3 section is unchanged (the confirmation-gate exemption lives here)" \
  "$SKILL" \
  "### Step 3 — Recognize the stop condition" \
  "### Step 4 — Persist the contract" \
  "7da64e3f34570be890ca21fcde988321ca4ad10b70ed87c46fe87411909cf7fe"
pin_section "SKILL.md \"does NOT do\" section is unchanged (the fudge prohibition lives here)" \
  "$SKILL" \
  "## What this skill does NOT do" \
  "## Composition with other skills" \
  "fdf329424220f1719941196992c05ad0ee859c174b88444bb90b5995e754fa19"

pin_case_digest "eval case B is unchanged (no criterion added that licenses the silent capture)" \
  "$CASE_B_NAME" \
  "dea5a9d5a6f66d93954ad3bc715d2910ea8c2237c9b085fc58107969d66eca68"
pin_case_set "the eval-case roster is unchanged (no sibling case added that contradicts 15 or 16)" \
  "e24be3f3078e1e3f675d41a7118bc87e3c1aa3bcb59e0952bcec4bbdc8a13bfa"

# The roster pin catches a case ADDED. It cannot see an existing sibling REWRITTEN in
# place: case 3 kept its name `lock-mode-does-not-fudge-gap` while its body was rewritten
# to say a gap with a defensible default is filled at that default — same roster hash,
# cases 15/16 untouched, suite green. The three narrative cases over these same two rules
# are therefore digested too. Any other case in this file is free to change; these three
# are not, because they speak to the defenses this suite exists to hold.
pin_case_digest "sibling case 2 still forbids folding a user choice into the Brief" \
  "auto-guard-never-folds-user-choice" \
  "73ef5bcb0cef36ff7f5523d93a4f3d8906285e9552f5e38be042b42376b367a7"
pin_case_digest "sibling case 3 still forbids fudging a gap in \`lock\` mode" \
  "lock-mode-does-not-fudge-gap" \
  "2ebe05ff4d99547ad9ce80a720fb8f0d807dfc72ceb16040d5fbc992eaaa376d"
pin_case_digest "sibling case 13 still requires named blockers instead of assumptions" \
  "unattended-run-emits-named-blockers-not-assumptions" \
  "1e82d5cddc52989a95d1847fd78a89280c73a6d026c1c841da47b1d374378a77"
# Three more cases rest on the same fact-vs-decision line the auto-guard draws, or on the
# no-silent-resolution rule. Case 8 was rewritten in place — "where a decision has a
# defensible conventional default, the skill resolves it on the user's behalf and records
# it as a captured assumption" — and licensed exactly the silent capture, undetected.
pin_case_digest "case 8 still asks decisions and only looks up facts" \
  "facts-looked-up-decisions-asked" \
  "869a487d5f0abe19cdbe5693b90beabb55f56fbdacf6642bedad62494ce029f5"
pin_case_digest "case 12 still refuses to read drift as consent" \
  "open-question-survives-an-unrelated-reply" \
  "e45fe64a00cf78e6dd089837e81c52d8a0947ccf924be6472c6f47eeadcd5942"
pin_case_digest "case 1 still resolves codebase-answerable questions without asking, and only those" \
  "relentless-me-mode-frontier-rounds" \
  "a1d108f02272c18494b5ca0a0c108385b776ff63bc423cb075c6e052810abc4a"

pin_file "case A fixture: the task context still plants the open decision" \
  "$FIXTURES/lock-stop-on-gap/task-context.md" \
  "b2452dfca23a4b50619e101ae68e77b9e63e656b8c1f918ae527c72218c5e176"
pin_file "case A fixture: the survey still leaves the plant unanswerable from the codebase" \
  "$FIXTURES/lock-stop-on-gap/codebase-survey.md" \
  "8a95e4b7159084837213da054cc40809312669b706f514c2bee1e29d247f5fa1"
pin_file "case B fixture: the task context still carries exactly one interactive residue" \
  "$FIXTURES/auto-guard-residue/task-context.md" \
  "06348abeb11eb53dd96e4b141f2cfd7b7becb8ae02cd3048e52baf9a0d52b843"
pin_file "case B fixture: the survey still closes four decisions and not the fifth" \
  "$FIXTURES/auto-guard-residue/codebase-survey.md" \
  "5c16e0ea2e5226182dd0316df922e0c8555a3db26f8d2703ca12cc8334a956fb"

# ===========================================================================
# CASE A — STOP-on-gap: `lock` halts on a genuinely-open decision
# ===========================================================================
echo
echo "--- Case A: lock STOP-on-gap ---"

# A1. The case still grades the halt itself, not incidental output.
if [[ -n "$CASE_A" ]]; then
  # The invocation under test must actually be `lock` — a case that drifted to `me` or
  # `auto` would grade a different path entirely.
  prompt_a="$(printf '%s' "$CASE_A" | jq -r '.prompt')"
  case "$prompt_a" in
  *"/planning:interview lock"*) ok "case A exercises the \`lock\` action" ;;
  *) fail "case A prompt no longer invokes \`lock\`: $prompt_a" ;;
  esac
  graded_mention "case A grades the HALT as a checkable expectation" "$CASE_A" "HALTS on that gap"
  graded_mention "case A forbids a Brief carrying a guessed disposition" "$CASE_A" "no \`## Brief\` is written that carries a chosen disposition"
  graded_mention "case A forbids burying the gap as a captured assumption" "$CASE_A" "\`### Captured assumptions\`"
  graded_mention "case A requires the gap be SURFACED with a choice" "$CASE_A" "SURFACED"
  graded_mention "case A keeps the halt SCOPED (the resolvable parts still synthesize)" "$CASE_A" "is not a refusal to lock anything"
  graded_mention "case A separates lock's confirmation exemption from STOP-on-gap" "$CASE_A" "does not license guessing"
fi

# A2. The Action Router's `lock` row carries the rule, not just the action.
pin "router \`lock\` row carries STOP-on-gap" "$SKILL" \
  "If a real gap surfaces during synthesis, STOP and surface it (do not fudge)"
within "router \`lock\` row sits in the Action Router table" "$SKILL" \
  "If a real gap surfaces during synthesis, STOP and surface it (do not fudge)" \
  "## Action Router" \
  "## Stance: supportive, depth-first, opinionated"

# A3. Step 1.5's routing line for `lock` repeats the halt at the point of routing.
pin_once "Step 1.5 routes \`lock\` with the halt attached" "$SKILL" \
  "If a gap surfaces mid-synthesis, STOP and surface — do not fudge."
within "the Step 1.5 \`lock\` routing line sits inside Step 1.5" "$SKILL" \
  "If a gap surfaces mid-synthesis, STOP and surface — do not fudge." \
  "### Step 1.5 — Auto-detect (default action only)" \
  "### Step 2 — Drive the frontier-rounds loop"

# A4. The negative-space declaration: fudging is named as something the skill does NOT do.
pin_once "\"does NOT do\" list names the fudge prohibition" "$SKILL" \
  "**Does not fudge gaps in \`lock\` mode**"
pin "the fudge prohibition names the halt and the fallback, not just the ban" "$SKILL" \
  "STOP and surface it. Fall back to \`auto\` or \`me\` instead of guessing"

# A5. The confirmation-gate exemption must not be readable as a STOP-on-gap exemption.
pin "confirmation-gate exemption preserves STOP-on-gap" "$SKILL" \
  "\`lock\` is exempt: invoking it IS the confirmation (its STOP-on-gap rule still applies)"

# A6. loop.md carries the operative STOP wording the case grades the offer against.
pin "loop.md carries the STOP-and-surface offer" "$LOOP" \
  "STOP and surface: *\"Found gap: <X>. Want me to ask, or capture as assumption with revisit trigger?\"* — never fudge."

# A7. A gap that goes to the user is a QUESTION, so the register gate keeps applying —
#     the no-question carve-out must stay scoped to the absence of questions.
pin "the register carve-out stays scoped to the absence of questions" "$SKILL" \
  "The carve-out is about the absence of questions, never about which action produced it"
pin "loop.md binds \`lock\`'s surfaced gap into the register" "$LOOP" \
  "a gap surfaced mid-synthesis is registered \`open\` when it goes to the user"

# A8. Whole-line pins — the five lines that ARE the STOP-on-gap defense. These catch the
#     neutralize-in-place edit the phrase pins above cannot: a qualifier appended to any of
#     them ("in practice a gap counts as real only when …") changes the line and fails here.
pin_exact "router \`lock\` row is byte-identical to the pinned defense" "$SKILL" \
  '| `lock` | **Force synthesis, no Q&A** | "Stop asking, just write it", "I'"'"'m clear, lock the brief" — skip auto-detect, synthesize directly. If a real gap surfaces during synthesis, STOP and surface it (do not fudge) |'
pin_exact "Step 1.5 \`lock\` routing line is byte-identical to the pinned defense" "$SKILL" \
  'For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface — do not fudge.'
pin_exact "the confirmation-gate paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Confirmation gate (`me` and `auto`):** an empty frontier is necessary but not sufficient — before persisting the contract or handing off, restate the shared understanding and get the user'"'"'s explicit confirmation that it is reached. Do not act on the interview'"'"'s output until they confirm. `lock` is exempt: invoking it IS the confirmation (its STOP-on-gap rule still applies).'
pin_exact "the fudge-prohibition bullet is byte-identical to the pinned defense" "$SKILL" \
  '- **Does not fudge gaps in `lock` mode** — if a true unknown surfaces during synthesis, STOP and surface it. Fall back to `auto` or `me` instead of guessing'
pin_exact "loop.md's \`lock\` STOP-on-gap line is byte-identical to the pinned defense" "$LOOP" \
  'When `lock` is invoked explicitly, skip auto-detect and synthesize. If a true gap is detected during synthesis, STOP and surface: *"Found gap: <X>. Want me to ask, or capture as assumption with revisit trigger?"* — never fudge.'

# ===========================================================================
# CASE B — auto-guard: the residue is asked, or blocked/USER-RESERVED, never assumed
# ===========================================================================
echo
echo "--- Case B: auto-detect auto-guard ---"

# B1. The case still grades the guard, and still accepts BOTH licensed outcomes while
#     rejecting the silent capture. This is the distinction the defense turns on.
if [[ -n "$CASE_B" ]]; then
  prompt_b="$(printf '%s' "$CASE_B" | jq -r '.prompt')"
  # `auto` is the empty/topic-only action: an explicit `me` or `lock` token would route
  # around Step 1.5 and grade a different path.
  case "$prompt_b" in
  *"/planning:interview lock"* | *"/planning:interview me"*)
    fail "case B prompt forces an explicit action; the auto-guard lives on the \`auto\` path: $prompt_b"
    ;;
  *"/planning:interview"*)
    ok "case B exercises the \`auto\` action (topic-only invocation)"
    ;;
  *)
    fail "case B prompt no longer invokes /planning:interview: $prompt_b"
    ;;
  esac
  graded_mention "case B grades the Step 1.5 Mixed outcome" "$CASE_B" "lands on the Mixed outcome"
  graded_mention "case B accepts the ASKED outcome" "$CASE_B" "ATTENDED, the residue is ASKED"
  graded_mention "case B accepts the unattended outcome as a \`blocked\` row" "$CASE_B" "recorded \`blocked\` in the register"
  graded_mention "case B requires the USER-RESERVED arbiter tag on that row" "$CASE_B" "\`arbiter: USER-RESERVED\`"
  graded_mention "case B holds the declared-not-sniffed condition" "$CASE_B" "never because the skill claims to detect a non-interactive environment"
  graded_mention "case B states the two outcomes are distinct and both acceptable" "$CASE_B" "Either outcome is acceptable and the two are DISTINCT"
  graded_mention "case B rejects the silent capture as disqualifying" "$CASE_B" "the silent capture is the disqualifying result"
  graded_mention "case B rejects over-application (facts must still synthesize)" "$CASE_B" "it does not block synthesis"
fi

# B2. The guard itself: named, singular, and inside the step that owns it.
pin_once "auto-guard is declared once, by name" "$SKILL" \
  "**Auto-guard — never decide an interactive choice for the user.**"
within "the auto-guard sits inside Step 1.5" "$SKILL" \
  "**Auto-guard — never decide an interactive choice for the user.**" \
  "### Step 1.5 — Auto-detect (default action only)" \
  "### Step 2 — Drive the frontier-rounds loop"

# B3. What the guard licenses, and what it forbids.
pin "the guard licenses only facts and unambiguous conventional defaults" "$SKILL" \
  "applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default"
pin "the guard forbids folding a user decision into the Brief" "$SKILL" \
  "do NOT fold it into the Brief"
pin "the guard names the ask-or-switch remedy" "$SKILL" \
  "STOP and either ask it inline (a residue round) or offer to switch"
pin "the guard names the silent capture as the failure it prevents" "$SKILL" \
  "Silently capturing such a choice as an assumption is the failure mode this guard prevents."

# B4. The unattended ladder — the guard's second licensed outcome. All four load-bearing
#     parts: declared-not-sniffed, the `blocked` row, the USER-RESERVED arbiter tag, and
#     the refusal to read silence as consent.
pin "unattended condition is declared by the caller, never sniffed" "$SKILL" \
  "The condition is **declared by the caller, never sniffed**"
pin "unattended user decisions become a \`blocked\` row + USER-RESERVED deferred question" "$SKILL" \
  "recorded \`blocked\` in the register, written to the Brief's \`### Deferred questions\` with **arbiter: USER-RESERVED**"
pin "the unattended path extends the guard rather than excepting it" "$SKILL" \
  "That extends the auto-guard rather than excepting it"
pin "silence is never confirmation" "$SKILL" \
  "never read absence of objection as confirmation"

# B5. The guard also holds INSIDE a round — an unanswered question is not consent to the
#     recommendation. Same defense, different surface.
pin "the guard holds inside rounds (no silent resolve-to-recommendation)" "$SKILL" \
  "NEVER silently resolve an unanswered question to its recommendation — the auto-guard applies inside rounds too"

# B6. loop.md's copies of both halves.
pin "loop.md restates the auto-guard's licensed territory" "$LOOP" \
  "A decision genuinely the user's (real tradeoffs, no codebase answer) is never synthesized silently"
pin "loop.md's unattended ladder never assumes a user decision" "$LOOP" \
  "**A decision that is genuinely the user's** — real tradeoffs, no codebase answer — is NEVER assumed."
pin "loop.md's ladder tags the deferred question USER-RESERVED" "$LOOP" \
  "tagged **arbiter: USER-RESERVED**"
pin "loop.md's ladder refuses to idle-wait" "$LOOP" \
  "stops on its blockers rather than holding the lane"
pin "loop.md's ladder refuses to read silence as confirmation" "$LOOP" \
  "absence of objection is not confirmation"
pin "loop.md binds the unattended blocker into the register" "$LOOP" \
  "a genuine user decision reached with nobody to answer is registered \`blocked\`"

# B7. Whole-line pins — the five lines that ARE the auto-guard. Same reason as A8: the
#     phrase pins cannot see a clause APPENDED to the guard ("**Exception:** … the guard is
#     satisfied by recording the residue under `### Captured assumptions`"), which leaves
#     every pinned phrase in place while inverting the rule. Whole-line equality does.
pin_exact "the auto-guard paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Auto-guard — never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path'"'"'s "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user'"'"'s — a design choice with real tradeoffs and no codebase answer — do NOT fold it into the Brief. STOP and either ask it inline (a residue round) or offer to switch: *"This is a real design decision, not mine to pick — answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.'
pin_exact "the unattended-path paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Unattended path — the guard holds, the run does not idle.** `/planning:interview` can be reached with no human to answer (a loop, a spawned worker, another skill'"'"'s chain). The condition is **declared by the caller, never sniffed** — there is no supported way for a session to observe that it is non-interactive. Unattended, codebase-resolvable and unambiguous-conventional decisions resolve as usual and are recorded `auto-resolved (unattended)`; a decision genuinely the user'"'"'s is recorded `blocked` in the register, written to the Brief'"'"'s `### Deferred questions` with **arbiter: USER-RESERVED**, and named as a blocker in the output. That extends the auto-guard rather than excepting it — the guard forbids the choice *disappearing*, and a named blocker is the choice made maximally visible. Stop on blockers; never wait indefinitely, and never read absence of objection as confirmation. Full ladder: [`context/loop.md`](context/loop.md) "Unattended path".'
pin_exact "loop.md's auto-guard line is byte-identical to the pinned defense" "$LOOP" \
  '**Auto-guard:** synthesize-directly applies ONLY to codebase-resolvable answers or unambiguous conventional defaults. A decision genuinely the user'"'"'s (real tradeoffs, no codebase answer) is never synthesized silently — ask it inline or offer `me` mode. See SKILL.md Step 1.5 "Auto-guard".'
pin_exact "loop.md's unattended ladder rung 3 is byte-identical to the pinned defense" "$LOOP" \
  '3. **A decision that is genuinely the user'"'"'s** — real tradeoffs, no codebase answer — is NEVER assumed. Record the row `blocked`, write the question into the Brief'"'"'s `### Deferred questions` led by its `Q<N>` id and tagged **arbiter: USER-RESERVED**, and name it as a blocker in the run'"'"'s output.'
pin_exact "loop.md's unattended ladder rungs 4-5 are byte-identical to the pinned defense" "$LOOP" \
  '4. **Never idle-wait.** A run with nobody to answer stops on its blockers rather than holding the lane.'
pin_exact "loop.md's unattended confirmation rung is byte-identical to the pinned defense" "$LOOP" \
  '5. **The confirmation gate cannot be satisfied unattended.** Report the contract as unconfirmed with its blocker list; absence of objection is not confirmation.'

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
