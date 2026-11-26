#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are deliberate throughout
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/interview/SKILL.md"
LOOP="$PLUGIN_DIR/skills/interview/context/loop.md"
SWEEP="$PLUGIN_DIR/skills/interview/context/assumption-sweep.md"
COVERAGE="$PLUGIN_DIR/skills/interview/context/coverage-prompt.md"
EARS="$PLUGIN_DIR/skills/interview/context/ears.md"
LANE_PAGE="$PLUGIN_DIR/skills/interview/context/lane-page.md"
AUDIT="$PLUGIN_DIR/skills/audit-answers/SKILL.md"
EVALS="$PLUGIN_DIR/skills/interview/evals/evals.json"
FIXTURES="$PLUGIN_DIR/skills/interview/evals/fixtures"

UPDATE_RULE="Read the git diff of this text first; the commit that updates the pin states, for each pin, old -> new and why the defense still holds."
REPIN_HINT="Re-pin with: bash plugins/planning/tests/repin.sh '<pin label text>'... '<why the defense still holds>' (or, where no test may run, plugins/planning/scripts/repin-digests.sh with the same arguments)"
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

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to grade $EVALS — this suite has no meaningful subset without it" >&2
  exit 1
fi

for f in "$SKILL" "$LOOP" "$SWEEP" "$COVERAGE" "$EARS" "$AUDIT" "$EVALS"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing required file: $f" >&2
    exit 1
  fi
done

if ! jq -e . "$EVALS" >/dev/null 2>&1; then
  echo "FAIL: $EVALS is not parsable JSON" >&2
  exit 1
fi

pin() {
  local label="$1" file="$2" phrase="$3"
  if grep -qF -- "$phrase" "$file"; then
    ok "$label"
  else
    fail "$label — phrase not found in ${file#"$PLUGIN_DIR/"}: \"$phrase\""
  fi
}

pin_once() {
  local label="$1" file="$2" phrase="$3" count
  count="$(grep -cF -- "$phrase" "$file")"
  if [[ "$count" -eq 1 ]]; then
    ok "$label"
  else
    fail "$label — expected exactly 1 occurrence in ${file#"$PLUGIN_DIR/"}, got $count: \"$phrase\""
  fi
}

pin_exact() {
  local label="$1" file="$2" line="$3"
  if grep -Fxq -- "$line" "$file"; then
    ok "$label"
  else
    fail "$label — no line in ${file#"$PLUGIN_DIR/"} matches the pinned defense text EXACTLY. The rule was reworded, extended, or qualified. Re-read it, confirm the defense still holds, then update the pin. Pinned: $line ${UPDATE_RULE}"
  fi
}

# shellcheck source=../scripts/lib/pin-digests.sh
if ! source "$PLUGIN_DIR/scripts/lib/pin-digests.sh"; then
  echo "FAIL: cannot load $PLUGIN_DIR/scripts/lib/pin-digests.sh" >&2
  exit 1
fi

pin_section() {
  local label="$1" file="$2" open="$3" close="$4" want="$5" got n_open n_close
  n_open="$(grep -Fxc -- "$open" "$file" || true)"
  n_close="$(grep -Fxc -- "$close" "$file" || true)"
  if [[ "$n_open" != "1" || "$n_close" != "1" ]]; then
    fail "$label — the section boundaries are no longer unique whole lines in ${file#"$PLUGIN_DIR/"} (\"$open\" x$n_open, \"$close\" x$n_close). A duplicated or renamed boundary moves the digested region, which is how a region pin gets silently emptied. Restore the headings, or re-anchor the pin and update the digest. ${UPDATE_RULE}"
    return
  fi
  got="$(section_digest "$file" "$open" "$close")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the section pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the section between \"$open\" and \"$close\" in ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). Anything added inside this section can qualify the defense it houses WITHOUT touching a pinned line. Re-read the section, confirm neither defense was weakened, then update the digest. ${UPDATE_RULE} ${REPIN_HINT}"
  fi
}

pin_frontmatter() {
  local label="$1" file="$2" want="$3" got
  got="$(frontmatter_digest "$file")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the frontmatter pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the YAML frontmatter of ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). Frontmatter is loaded before any section, so a qualifier in ANY key here reaches every invocation. Re-read it, confirm neither defense was weakened, then update the digest. ${UPDATE_RULE} ${REPIN_HINT}"
  fi
}

pin_case_digest() {
  local label="$1" name="$2" want="$3" got
  got="$(case_digest "$EVALS" "$name")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the case pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — eval case \"$name\" changed (want $want, got $got). A criterion may have been added that contradicts one already pinned. Re-read the case, confirm it still rejects the silent capture, then update the digest. ${UPDATE_RULE} ${REPIN_HINT}"
  fi
}

pin_file() {
  local label="$1" file="$2" want="$3" got
  got="$(file_digest "$file")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the fixture pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — ${file#"$PLUGIN_DIR/"} changed (want $want, got $got). This fixture IS the case's plant: if it no longer plants a genuinely-open decision (case A) or a resolved-but-one context (case B), the case grades nothing. Re-read it, confirm the plant survives, then update the digest. ${UPDATE_RULE} ${REPIN_HINT}"
  fi
}

pin_case_set() {
  local label="$1" want="$2" got
  got="$(case_set_digest "$EVALS")"
  if [[ "$got" == "NO-DIGEST-TOOL" ]]; then
    fail "$label — neither sha256sum nor shasum is available; the roster pin cannot be graded"
  elif [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label — the eval-case roster in ${EVALS#"$PLUGIN_DIR/"} changed (want $want, got $got). Adding a case is fine; adding one that contradicts case 15 or 16 is not. Confirm no new case licenses the silent capture or a fudged gap, then update the digest. ${UPDATE_RULE} ${REPIN_HINT}"
  fi
}

line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

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

case_json() {
  jq -c --arg n "$1" '.evals[] | select(.name == $n)' "$EVALS"
}

case_present() {
  local arm="$1" name="$2" json="$3"
  if [[ -n "$json" ]]; then
    ok "case $arm present in evals.json: $name"
  else
    fail "case $arm missing from evals.json: expected an eval case named $name"
  fi
}

declares_both_fixtures() {
  local arm="$1" json="$2" declared
  [[ -n "$json" ]] || return 0
  declared="$(printf '%s' "$json" | jq -r '(.files // []) | length')"
  if [[ "$declared" -eq 2 ]]; then
    ok "case $arm declares both fixtures in files[]"
  else
    fail "case $arm declares $declared fixture(s) in files[]; expected 2"
  fi
}

graded_mention() {
  local label="$1" json="$2" needle="$3" text
  text="$(printf '%s' "$json" | jq -r '(.expectations // []) | join(" ")')"
  case "$text" in
  *"$needle"*) ok "$label" ;;
  *) fail "$label — no graded expectation mentions: \"$needle\"" ;;
  esac
}

CASE_A_NAME="lock-halts-on-planted-open-decision"
CASE_B_NAME="auto-residue-asked-or-user-reserved-never-assumed"

CASE_A="$(case_json "$CASE_A_NAME")"
CASE_B="$(case_json "$CASE_B_NAME")"

case_present A "$CASE_A_NAME" "$CASE_A"
case_present B "$CASE_B_NAME" "$CASE_B"

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

declares_both_fixtures A "$CASE_A"
declares_both_fixtures B "$CASE_B"

pin_frontmatter "SKILL.md frontmatter is unchanged (the always-loaded routing surface, every key)" \
  "$SKILL" \
  "66f4633a977b9e9855874b98d242b7cc45a2205588f616cb8867cf5d518b97da"

pin_section "SKILL.md Gates section is unchanged (the early twin of the five gates)" \
  "$SKILL" \
  "## Gates" \
  "## Action Router" \
  "fe5b699cb44bca9188c8d7155c57260c875534a45b6acabe62238c60405d6b83"
for gate_line in \
  "**The user's decisions are never synthesized.**" \
  "**A gap during \`lock\` synthesis halts the run.**" \
  "**The register gate runs before the contract locks.**" \
  "**The confirmation gate holds the contract until the user confirms.**" \
  "**The Brief is cross-checked once it exists.**"; do
  pin_once "Gates names: $gate_line" "$SKILL" "$gate_line"
  within "Gates holds: $gate_line" "$SKILL" "$gate_line" "## Gates" "## Action Router"
done

pin_section "SKILL.md Stance section is unchanged (the in-round no-silent-resolve rule lives here)" \
  "$SKILL" \
  "## Stance: supportive, depth-first, opinionated" \
  "## The interview loop" \
  "cd04a7e858fbdc9510553eb519d3ad8630c77e8b26638f1f87a252424fe95474"
pin_section "SKILL.md interview-loop preamble is unchanged (it governs every step below it)" \
  "$SKILL" \
  "## The interview loop" \
  "### Step 1. Survey before you ask" \
  "c84a3506c3410b64938b898238a53f502e5e411522ea61e7444f3ad382a21860"
pin_section "loop.md open-question register section is unchanged (it binds gaps and blockers to the gate)" \
  "$LOOP" \
  "## The open-question register" \
  "## Step 3. Recognize the stop condition" \
  "631b09e8dd5f82e53de71fa31d652918dfb37538034259c38cde6a1f00bdeaa1"
pin_section "loop.md Step 3 section is unchanged (it twins the confirmation-gate exemption)" \
  "$LOOP" \
  "## Step 3. Recognize the stop condition" \
  "## Step 4. Section guidance for the Brief" \
  "98a128e1cbeb6173043630fc660aa334972843da965623aeb598f650ca9b3037"
pin_section "loop.md Step 4 section is unchanged (it twins the USER-RESERVED arbiter guidance)" \
  "$LOOP" \
  "## Step 4. Section guidance for the Brief" \
  "## Brief" \
  "0455c59b5d60e559d5da68d9cb6a77afaa41faf0a324c2ef97ec1df73dd425e5"

pin_section "SKILL.md Step 1 section is unchanged (a preamble here reads as governing the two rules below)" \
  "$SKILL" \
  "### Step 1. Survey before you ask" \
  "### Step 1.5. Auto-detect (default action only)" \
  "0c42ce895e27712457fe1cfafdd734e9d6e22fde8e239fcfd124b8923b3fc83b"
pin_section "SKILL.md Step 4 section is unchanged (the Brief's assumption machinery lives here)" \
  "$SKILL" \
  "### Step 4. Persist the Brief" \
  "### Step 5. Hand off" \
  "78ad563aa030fde8d01483f8bd0ffd0fffad22a36873596c2253532b07328549"
pin_section "SKILL.md Step 1.5 section is unchanged (auto-guard + unattended + \`lock\` routing live here)" \
  "$SKILL" \
  "### Step 1.5. Auto-detect (default action only)" \
  "### Step 2. Drive the frontier-rounds loop" \
  "30892caae26855fd0f6e1a829c2abccd26fcab5b4f18642662dd8f538a2744bf"
pin_section "loop.md Step 1.5 section is unchanged (loop's auto-guard + \`lock\` STOP line live here)" \
  "$LOOP" \
  "## Step 1.5. Auto-detect: gap analysis without asking" \
  "## Step 2. Drive the decision tree" \
  "5a65d20ba8f7988d3eba22ff8deaebcde7c7783d6f8730369b9c42ba97b3d4f3"
pin_section "loop.md Unattended path section is unchanged (the ladder lives here)" \
  "$LOOP" \
  "### Unattended path" \
  "### Gate before locking" \
  "08c2539a439ea7b544d4f5655d93046b0554f81484f40b5a7c30238866e3a85c"

pin_case_digest "eval case A is unchanged (no criterion added that contradicts the halt)" \
  "$CASE_A_NAME" \
  "127e69330697737f80e82556cfc7e67492203979a16616fac732992c3654f490"
pin_section "SKILL.md Action Router section is unchanged (the \`lock\` row and its reading live here)" \
  "$SKILL" \
  "## Action Router" \
  "## Stance: supportive, depth-first, opinionated" \
  "0834710ccd7fc6f929fc206bab2abfdb1e65312b3d909704c8ccfd794593b83c"
pin_section "SKILL.md Step 3 section is unchanged (the confirmation-gate exemption lives here)" \
  "$SKILL" \
  "### Step 3. Recognize the stop condition" \
  "### Step 4. Persist the Brief" \
  "f9168797058fc219ebeaf7585123f9ea19a353754f28b454afe26e7cd6050afb"
pin_section "SKILL.md \"does NOT do\" section is unchanged (the fudge prohibition lives here)" \
  "$SKILL" \
  "## What this skill does NOT do" \
  "## Next" \
  "7a4386a0469a6a1ecdd8269e727dd9527dc56d9253bd3527757b61d71897ba0e"

pin_section "SKILL.md Step 2 section is unchanged (constraint ledger, candidates, currency, tripwire, sweep)" \
  "$SKILL" \
  "### Step 2. Drive the frontier-rounds loop" \
  "### Step 3. Recognize the stop condition" \
  "eb231ceeea553fefdaae908e4367fb3f8cb1c3a0456d2a632310d23bcce158f5"
pin_section "loop.md Step 2 section is unchanged (constraint ledger rows, process-change definition)" \
  "$LOOP" \
  "## Step 2. Drive the decision tree" \
  "## Relentless \`me\` mode mechanics" \
  "ac1a9be7d6b5b2b517954fae534f70a91dd68172e60eb2f28b62968226e729f5"
pin_section "loop.md relentless mechanics section is unchanged (late commitment rows take the next free id)" \
  "$LOOP" \
  "## Relentless \`me\` mode mechanics" \
  "## The open-question register" \
  "713bf5f475597226013d471a5cc1a41a4579e256b844c69d8d5c9b28aea15a01"
pin_file "context/assumption-sweep.md is unchanged (the sweep's scope, item shape, and disposition)" \
  "$SWEEP" \
  "7741202424622a250ffaf696fd0bad31877dc4ad425e03490942d0766d151478"
pin_file "context/coverage-prompt.md is unchanged (the coverage prompt exempts itself and nothing else)" \
  "$COVERAGE" \
  "5f41e2094807dd0e0409f52f38a0683e1b121f48c8429e441fb63873308c46cf"
pin_file "context/ears.md is unchanged (the EARS tags and the format resolution ladder)" \
  "$EARS" \
  "2707011ce51e3057290cff39b3d5509e20778e49f78393709290ecd3971f7b8c"
pin_section "audit-answers Step 1 section is unchanged (the never-auto floor, hedged rows included)" \
  "$AUDIT" \
  "### Step 1. Assemble the answer set, holding the never-auto floor" \
  "### Step 2. Dispatch fresh-context validators" \
  "f093e2ef1bf65a8408ec8c5609b2586146754c4897143cc5030314c9a24f1922"
pin_section "audit-answers Step 4 section is unchanged (hedged rows always reach the human)" \
  "$AUDIT" \
  "### Step 4. Merge and triage" \
  "### Step 5. Human confirmation" \
  "bdbde2c21e6f1c7bc05b752b25541ce15d59f703ba6d83a936d64842e0c1fd44"

pin_case_digest "eval case B is unchanged (no criterion added that licenses the silent capture)" \
  "$CASE_B_NAME" \
  "dea5a9d5a6f66d93954ad3bc715d2910ea8c2237c9b085fc58107969d66eca68"
pin_case_set "the eval-case roster is unchanged (no sibling case added that contradicts 15 or 16)" \
  "7bd78ae7a7bc7a32988b8a7b526a189373ac3fa961f79f7aa56c826a280d588b"

pin_case_digest "sibling case 2 still forbids folding a user choice into the Brief" \
  "auto-guard-never-folds-user-choice" \
  "73ef5bcb0cef36ff7f5523d93a4f3d8906285e9552f5e38be042b42376b367a7"
pin_case_digest "sibling case 3 still forbids fudging a gap in \`lock\` mode" \
  "lock-mode-does-not-fudge-gap" \
  "514f6a7c3dff3378cd22d99af4dcca604400338227d2e3b038d02cccc636e866"
pin_case_digest "sibling case 13 still requires named blockers instead of assumptions" \
  "unattended-run-emits-named-blockers-not-assumptions" \
  "6633823b6dc62312f3fa505e3959e0f23620da1ea0871e45f01ad41c34064efb"
pin_case_digest "case 8 still asks decisions and only looks up facts" \
  "facts-looked-up-decisions-asked" \
  "bedb9fd8e5923395d229e36cf50479530e58abcd8503a3ae989212162b789c45"
pin_case_digest "case 12 still refuses to read drift as consent" \
  "open-question-survives-an-unrelated-reply" \
  "e45fe64a00cf78e6dd089837e81c52d8a0947ccf924be6472c6f47eeadcd5942"
pin_case_digest "case 25 still refuses to settle a row on a superseded recommendation" \
  "out-of-band-return-supersedes-before-the-reply" \
  "a3e7ffd4412ccfb51465f0be3d871221a6c288d53131c8436ef6025bc30974bd"
pin_case_digest "case 1 still resolves codebase-answerable questions without asking, and only those" \
  "relentless-me-mode-frontier-rounds" \
  "1065f9d322d8ae3b5179ac13ec75e615044f42b7ada5455737d285048032a217"

pin_file "case A fixture: the task context still plants the open decision" \
  "$FIXTURES/lock-stop-on-gap/task-context.md" \
  "27ffc38bf30b3fcc6cfea643f24acbfe808a8e8dce16e9d32cadc633ec15bb1c"
pin_file "case A fixture: the survey still leaves the plant unanswerable from the codebase" \
  "$FIXTURES/lock-stop-on-gap/codebase-survey.md" \
  "b296189dba1e3d4a81bf8bbf3f49ddae3d51bde9be8e8bf955f3c292e73a9961"
pin_file "case B fixture: the task context still carries exactly one interactive residue" \
  "$FIXTURES/auto-guard-residue/task-context.md" \
  "18e4cc465e8e4f5eb1fe7c8f2ba4ff78e852b9ed90ecc5cdb5545d6a3303d859"
pin_file "case B fixture: the survey still closes four decisions and not the fifth" \
  "$FIXTURES/auto-guard-residue/codebase-survey.md" \
  "5ea7bfd889b75562e662ed5a951bee32ac16d6f4d7013538daacc595df853f06"

echo
echo "--- Case A: lock STOP-on-gap ---"

if [[ -n "$CASE_A" ]]; then
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

pin "router \`lock\` row carries STOP-on-gap" "$SKILL" \
  "If a real gap surfaces during synthesis, STOP and surface it (do not fudge)"
within "router \`lock\` row sits in the Action Router table" "$SKILL" \
  "If a real gap surfaces during synthesis, STOP and surface it (do not fudge)" \
  "## Action Router" \
  "## Stance: supportive, depth-first, opinionated"

pin_once "Step 1.5 routes \`lock\` with the halt attached" "$SKILL" \
  "If a gap surfaces mid-synthesis, STOP and surface; do not fudge."
within "the Step 1.5 \`lock\` routing line sits inside Step 1.5" "$SKILL" \
  "If a gap surfaces mid-synthesis, STOP and surface; do not fudge." \
  "### Step 1.5. Auto-detect (default action only)" \
  "### Step 2. Drive the frontier-rounds loop"

pin_once "\"does NOT do\" list names the fudge prohibition" "$SKILL" \
  "**Does not fudge gaps in \`lock\` mode**"
pin "the fudge prohibition names the halt and the fallback, not just the ban" "$SKILL" \
  "STOP and surface it. Fall back to \`auto\` or \`me\` instead of guessing"

pin "confirmation-gate exemption preserves STOP-on-gap" "$SKILL" \
  "its invocation confirms the rest (its STOP-on-gap rule still applies)"

pin "loop.md carries the STOP-and-surface offer" "$LOOP" \
  "STOP and surface: *\"Found gap: <X>. Want me to ask, or capture as assumption with recheck trigger?\"* Never fudge."

pin "the register carve-out stays scoped to the absence of questions" "$SKILL" \
  "The carve-out is about the absence of questions, never about which action produced it"
pin "loop.md binds \`lock\`'s surfaced gap into the register" "$LOOP" \
  "a gap surfaced mid-synthesis is registered \`open\` when it goes to the user"

pin "loop.md fires the out-of-band check on non-user content" "$LOOP" \
  "non-user content reaching the transcript while a round is open"
pin "loop.md keys the out-of-band check on relevance, not arrival" "$LOOP" \
  "The trigger is RELEVANCE, not arrival"
pin "loop.md names a contradicted recommendation as superseded" "$LOOP" \
  "naming the superseded recommendation as superseded"
pin "loop.md resolves an environment-answered open row" "$LOOP" \
  "Resolve it and STATE the answer"
pin "loop.md restates every open row in full after out-of-band output" "$LOOP" \
  "**Restate every open row in full.**"
pin "loop.md refuses to hold the round for a pending dispatch" "$LOOP" \
  "**This does not hold the round.**"
pin "loop.md floors the out-of-band restate on the next user reply" "$LOOP" \
  "The floor is the next user reply."
pin "loop.md processes queued out-of-band output before the same-turn reply" "$LOOP" \
  "When a user reply and queued out-of-band output share a turn, process the queued output first."
pin "SKILL.md carries the out-of-band check beside the register rule" "$SKILL" \
  "**Out-of-band output gets the same check, keyed on relevance.**"

pin "SKILL.md lists every part of a bundled recommendation" "$SKILL" \
  "**A recommendation that fixes more than one decision lists every part.**"
pin "SKILL.md per-question template carries the commitment block" "$SKILL" \
  "[Commits you to: <ONLY when the recommendation fixes more than one decision"
pin "SKILL.md: an unlisted sub-decision is not decided by the headline" "$SKILL" \
  "is not decided by any answer to the headline"
pin "SKILL.md: an accept-shorthand that resolved commitment rows names them" "$SKILL" \
  "When an accept-shorthand resolves commitment rows, name their \`Q<N>\` ids in one line."
pin "SKILL.md: a page accept resolves only ticked parts" "$SKILL" \
  "(on the page, only the parts the user ticks)"
pin "loop.md: parts of a page question answered with an alternative or an own answer are withdrawn" "$LOOP" \
  "An alternative or an \`own\` answer replaces the recommendation and withdraws the parts, so they do not reach the Brief"
pin "loop.md defines commitment rows" "$LOOP" \
  "**Commitment rows.**"
pin "loop.md: an alternative or rejection withdraws the commitment rows" "$LOOP" \
  "sets each to \`withdrawn\` with \`pruned by Q5 = <answer>\`"
pin "loop.md: unattended, each part takes the ladder on its own" "$LOOP" \
  "a codebase-resolvable headline does not make its parts resolvable"
pin "SKILL.md: a hedged reply resolves only the headline" "$SKILL" \
  "**A hedged reply resolves only the headline.**"
pin "SKILL.md: a hedged accept-shorthand is not an accept-shorthand" "$SKILL" \
  "A hedged accept-shorthand (\"accept all?\") is not an accept-shorthand."
pin "loop.md defines the hedged flag" "$LOOP" \
  "resolves to \`answered\` with \`hedged: <answer>\`"
pin "loop.md: the confirmation restate lists every hedged row" "$LOOP" \
  "lists every row carrying \`hedged:\`, and every \`free-text:\` row whose answer is hedged, for explicit confirmation"
pin "loop.md: a hedged own answer typed on the page gets the same echo" "$LOOP" \
  "A hedged \"Own answer\" typed on the page gets the same echo on its wake"
pin "SKILL.md: the Stance routes the question surface through the surface registry's resolution" "$SKILL" \
  "The surface follows the resolution in \"Question lanes\" above"
pin "SKILL.md: on the page, commitment parts are \`commits\` entries" "$SKILL" \
  "on the page, its parts are the question's \`commits\` entries"
pin "loop.md defines commitment parts on the page" "$LOOP" \
  "**Commitment parts on the page.**"
pin "loop.md: an accepted or hedged page row with an unticked part exports open" "$LOOP" \
  "an accepted or hedged row with an unticked part exports \`open\`"
pin "loop.md: a mirrored terminal answer ticks no part" "$LOOP" \
  "a terminal answer mirrored with \`record-terminal\` ticks none"
pin "loop.md: a hedged reply is never mirrored as accept" "$LOOP" \
  "never as \`accept\`, which records accept-all"
pin "loop.md: the read-only decision table numbers each part" "$LOOP" \
  "The read-only decision table gives each part its own row number"

pin "SKILL.md keeps a running constraint ledger" "$SKILL" \
  "**Keep a running constraint ledger.**"
pin "SKILL.md: a stated constraint is written at once as confirmed" "$SKILL" \
  "Every constraint the user states is written at once as \`confirmed\`"
pin "SKILL.md: an upstream constraint is inherited" "$SKILL" \
  "a constraint taken from an upstream artifact is \`inherited\`"
pin "SKILL.md: every recommendation names the constraints it was checked against" "$SKILL" \
  "\`Checked against: V1 ships without SSO; no new runtime dependencies\` or \`Checked against: none\`"
pin "lane-page.md: on the page the citation opens the question's facts field" "$LANE_PAGE" \
  "On the page it opens the question's \`facts\` field, each constraint named in words"
pin "lane-page.md: the page is the lane whose restatement box offers commitment ticks" "$LANE_PAGE" \
  "this lane's restatement box offers commitment ticks, so SKILL.md's exception applies here"
pin "lane-page.md: the page's Brief cross-check adds --surface" "$LANE_PAGE" \
  "Step 4, Brief cross-check (and its Gates twin): add \`--surface '<data_dir>'\`"
pin_section "lane-page.md steps section is unchanged (the page's part of the Step 3 exception lives here)" \
  "$LANE_PAGE" \
  "## SKILL.md steps on this lane" \
  "## Exit codes" \
  "ae49eb827feabdbdabbb84f03622a2dcf7ecce910a9b8e2a849f512fe98e3abd"
pin "SKILL.md: a question citing a constraint is never asked on a card" "$SKILL" \
  "one that cites a constraint is asked in prose"
pin "SKILL.md: a relied-on inherited constraint is asked as a register row" "$SKILL" \
  "An \`inherited\` constraint the Brief relies on is asked as a register row at ask-time"
pin "SKILL.md: in lock a relied-on inherited constraint is a gap that STOPs" "$SKILL" \
  "In \`lock\` a relied-on inherited constraint is a gap: STOP and surface it (Step 1.5)"
pin "SKILL.md: in auto synthesis a relied-on inherited constraint makes the path Mixed" "$SKILL" \
  "in \`auto\` direct synthesis it makes the path Mixed and is asked in the residue round"
pin "SKILL.md: composed artifacts are candidates" "$SKILL" \
  "is a candidate, never a recommendation, until re-derived against the constraint ledger"
pin "SKILL.md: a mid-interview research brief carries the constraint ledger" "$SKILL" \
  "dispatched mid-interview carries the constraint ledger verbatim"
pin "SKILL.md labels evidence by when it was true" "$SKILL" \
  "**Label evidence by when it was true.**"
pin "SKILL.md: past-only evidence never alone grounds a recommendation" "$SKILL" \
  "past-only evidence never alone grounds a recommendation"
pin "SKILL.md defines a process change" "$SKILL" \
  "(a changelog, commit, ticket, or user statement dated after the evidence window) or cannot rule out"
pin "SKILL.md carries the mechanism tripwire" "$SKILL" \
  "**What, not how: the mechanism tripwire.**"
pin "SKILL.md: \"at planning\" defers open mechanism rows" "$SKILL" \
  "every still-\`open\` mechanism row, commitment rows included, becomes \`deferred\`"
pin "SKILL.md: \"now\" is recorded in the Brief's Constraints" "$SKILL" \
  "the Brief's Constraints records that this topic overrides \"does not plan implementation\""
pin "SKILL.md sweeps for assumptions before Step 3" "$SKILL" \
  "**Sweep for assumptions before Step 3.**"
pin "SKILL.md: a sweep that adds an open row returns the run to Step 2" "$SKILL" \
  "Step 3 is reached when a sweep adds no \`open\` row"
pin "SKILL.md: the confirmation restatement carries a recap generated from the register on disk" "$SKILL" \
  "generated from the register on disk, never from the transcript, so it survives a compaction"
pin "SKILL.md: each recap line carries the question text, not only its id and resolution" "$SKILL" \
  "shaped \`Q<N> <status>: <question text> (<resolution>)\`"
pin "SKILL.md: the Step 4 cross-check names the nine Brief template headings it requires" "$SKILL" \
  "the Brief carries all nine template headings"
pin "SKILL.md: the procedure check is cited by exit code, not by the model's account" "$SKILL" \
  "cite its exit code and \`procedure=\` field as the evidence that the procedure ran, never your own account of it"
pin "SKILL.md: a non-zero procedure exit halts the confirmation request" "$SKILL" \
  "A non-zero exit HALTS the confirmation request"
pin "SKILL.md: Step 3 names the model-judgment items the procedure check does not verify" "$SKILL" \
  "whether the Step 1 survey grounded the questions, whether the domain was classified, whether register rows were written at ask-time rather than answer-time, and whether the frontier was recomputed between rounds"
pin "SKILL.md: the recap and audit-answers neither compose nor duplicate each other" "$SKILL" \
  "neither composes nor duplicates it"
pin "audit-answers: states its relationship to the interview's recap and procedure check" "$AUDIT" \
  "neither composes nor duplicates the other"
pin "surface.md: the restate op carries the same register-sourced recap" \
  "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "The restatement carries the same register-sourced recap as Step 3"
pin "loop.md defines the constraint ledger row shape" "$LOOP" \
  "\`- C<N> | confirmed|inherited | <constraint> | <source>\`"
pin "loop.md defines a process change" "$LOOP" \
  "(a changelog, commit, ticket, or user statement dated after the evidence window) or cannot rule out"
pin "loop.md: a late commitment row takes the next free id" "$LOOP" \
  "takes the next free \`Q<N>\` and names its headline in the question field"
pin "assumption-sweep.md: the sweep never dispatches a fork" "$SWEEP" \
  "Request any subagent type but \`fork\`."
pin "assumption-sweep.md: sweep ids never reach the register" "$SWEEP" \
  "\`S<N>\` never reaches the register"
pin "assumption-sweep.md: an open row returns the run to Step 2" "$SWEEP" \
  "Any \`open\` row it adds returns the run to Step 2"
pin "assumption-sweep.md points the hedged relist at loop.md" "$SWEEP" \
  "loop.md \"Hedged flag\""
pin "audit-answers: a hedged row never closes on CONFIRMED" "$AUDIT" \
  "never closes on a CONFIRMED verdict"
pin "audit-answers: a free-text row is validated and flagged" "$AUDIT" \
  "A \`free-text:\` row is validated like any answer and flagged"
pin "surface.md routes an accept-audit event to audit-answers" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "the skill routes the round to \`/planning:audit-answers\`"
pin "surface.md lists the accept-audit event kind" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "| \`accept-audit\` |"
pin "surface.md: the page's confirmation gate waits for confirm-understanding" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "2. Wait for a \`confirm-understanding\` event."
pin "surface.md: the page's restate keeps the full recap" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "Leave out \`--changed\` here"
pin "surface.md: the tick exception covers only unticked commitments, any other defect halts" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "since the restatement box offers their ticks; a hedged row's condition is still open, so it halts; any other defect halts it, as SKILL.md Step 3 says."
pin "surface.md: the page's Brief cross-check adds --surface" "$PLUGIN_DIR/skills/interview/context/surface.md" \
  "On this lane, pass \`--surface '<data_dir>'\` to the Step 4 \`--brief --procedure\` gate"

pin_exact "router \`lock\` row is byte-identical to the pinned defense" "$SKILL" \
  '| `lock` | **Force synthesis, one problem question** | "Stop asking, just write it", "I'"'"'m clear, lock the brief". Skip auto-detect, confirm the one-line problem with one question, synthesize directly. If a real gap surfaces during synthesis, STOP and surface it (do not fudge) |'
pin_exact "Step 1.5 \`lock\` routing line is byte-identical to the pinned defense" "$SKILL" \
  'For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface; do not fudge.'
pin_exact "the confirmation-gate paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Confirmation gate (`me` and `auto`):** that no question is left to ask does not end the interview on its own. Before persisting the contract or handing off, restate the shared understanding, opening with the one-line problem, and get the user'"'"'s explicit confirmation that it is reached. Do not act on the interview'"'"'s output until they confirm. `lock` confirms the problem with one question, registered like any row; its invocation confirms the rest (its STOP-on-gap rule still applies).'
pin_exact "the fudge-prohibition bullet is byte-identical to the pinned defense" "$SKILL" \
  '- **Does not fudge gaps in `lock` mode**. If a true unknown surfaces during synthesis, STOP and surface it. Fall back to `auto` or `me` instead of guessing'
pin_exact "loop.md's \`lock\` STOP-on-gap line is byte-identical to the pinned defense" "$LOOP" \
  'When `lock` is invoked explicitly, skip auto-detect and synthesize. If a true gap is detected during synthesis, STOP and surface: *"Found gap: <X>. Want me to ask, or capture as assumption with recheck trigger?"* Never fudge.'

echo
echo "--- Case B: auto-detect auto-guard ---"

if [[ -n "$CASE_B" ]]; then
  prompt_b="$(printf '%s' "$CASE_B" | jq -r '.prompt')"
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

pin_once "auto-guard is declared once, by name" "$SKILL" \
  "**Auto-guard. Never decide an interactive choice for the user.**"
within "the auto-guard sits inside Step 1.5" "$SKILL" \
  "**Auto-guard. Never decide an interactive choice for the user.**" \
  "### Step 1.5. Auto-detect (default action only)" \
  "### Step 2. Drive the frontier-rounds loop"

pin "the guard licenses only facts and unambiguous conventional defaults" "$SKILL" \
  "applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default"
pin "the guard forbids folding a user decision into the Brief" "$SKILL" \
  "do NOT fold it into the Brief"
pin "the guard names the ask-or-switch remedy" "$SKILL" \
  "STOP and either ask it inline (a residue round) or offer to switch"
pin "the guard names the silent capture as the failure it prevents" "$SKILL" \
  "Silently capturing such a choice as an assumption is the failure mode this guard prevents."

pin "unattended condition is declared by the caller, never sniffed" "$SKILL" \
  "The condition is **declared by the caller, never sniffed**"
pin "unattended user decisions become a \`blocked\` row + USER-RESERVED deferred question" "$SKILL" \
  "recorded \`blocked\` in the register, written to the Brief's \`### Deferred questions\` with **arbiter: USER-RESERVED**"
pin "the unattended path extends the guard rather than excepting it" "$SKILL" \
  "That extends the auto-guard rather than excepting it"
pin "silence is never confirmation" "$SKILL" \
  "never read absence of objection as confirmation"

pin "the guard holds inside rounds (no silent resolve-to-recommendation)" "$SKILL" \
  "NEVER silently resolve an unanswered question to its recommendation; the auto-guard applies inside rounds too"

pin "loop.md restates the auto-guard's licensed territory" "$LOOP" \
  "A decision genuinely the user's (real tradeoffs, no codebase answer) is never synthesized silently"
pin "loop.md's unattended ladder never assumes a user decision" "$LOOP" \
  "**A decision that is genuinely the user's**, with real tradeoffs and no codebase answer, is NEVER assumed."
pin "loop.md's ladder tags the deferred question USER-RESERVED" "$LOOP" \
  "tagged **arbiter: USER-RESERVED**"
pin "loop.md's ladder refuses to idle-wait" "$LOOP" \
  "stops on its blockers rather than holding the lane"
pin "loop.md's ladder refuses to read silence as confirmation" "$LOOP" \
  "absence of objection is not confirmation"
pin "loop.md binds the unattended blocker into the register" "$LOOP" \
  "a genuine user decision reached with nobody to answer is registered \`blocked\`"

pin_exact "the auto-guard paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Auto-guard. Never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path'"'"'s "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user'"'"'s, a design choice with real tradeoffs and no codebase answer, do NOT fold it into the Brief. STOP and either ask it inline (a residue round) or offer to switch: *"This is a real design decision, not mine to pick. Answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.'
pin_exact "the unattended-path paragraph is byte-identical to the pinned defense" "$SKILL" \
  '**Unattended path: the guard holds, the run does not idle.** `/planning:interview` can be reached with no human to answer (a loop, a spawned worker, another skill'"'"'s chain). The condition is **declared by the caller, never sniffed**: the caller knows whether a person is there to answer, and the skill would only be guessing. Unattended, codebase-resolvable and unambiguous-conventional decisions resolve as usual and are recorded `auto-resolved (unattended)`; a decision genuinely the user'"'"'s is recorded `blocked` in the register, written to the Brief'"'"'s `### Deferred questions` with **arbiter: USER-RESERVED**, and named as a blocker in the output. That extends the auto-guard rather than excepting it. The guard forbids the choice *disappearing*, and a named blocker is the choice made maximally visible. Stop on blockers; never wait indefinitely, and never read absence of objection as confirmation. Full ladder: [`context/loop.md`](context/loop.md) "Unattended path".'
pin_exact "loop.md's auto-guard line is byte-identical to the pinned defense" "$LOOP" \
  '**Auto-guard:** synthesize-directly applies ONLY to codebase-resolvable answers or unambiguous conventional defaults. A decision genuinely the user'"'"'s (real tradeoffs, no codebase answer) is never synthesized silently. Ask it inline or offer `me` mode. See SKILL.md Step 1.5 "Auto-guard".'
pin_exact "loop.md's unattended ladder rung 3 is byte-identical to the pinned defense" "$LOOP" \
  '3. **A decision that is genuinely the user'"'"'s**, with real tradeoffs and no codebase answer, is NEVER assumed. Record the row `blocked`, write the question into the Brief'"'"'s `### Deferred questions` led by its `Q<N>` id and tagged **arbiter: USER-RESERVED**, and name it as a blocker in the run'"'"'s output.'
pin_exact "loop.md's unattended ladder rung 4 is byte-identical to the pinned defense" "$LOOP" \
  '4. **Never idle-wait.** A run with nobody to answer stops on its blockers rather than holding the lane.'
pin_exact "loop.md's unattended confirmation rung is byte-identical to the pinned defense" "$LOOP" \
  '5. **The confirmation gate cannot be satisfied unattended.** Report the contract as unconfirmed with its blocker list; absence of objection is not confirmation.'

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
