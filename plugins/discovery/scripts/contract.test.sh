#!/usr/bin/env bash
# Contract test for the discovery plugin's cross-file statements.
#
# The two sibling suites (`check-dispatch-artifact.test.sh`,
# `check-coverage-complete.test.sh`) grade a script. This one grades the
# *documents*, because this plugin's observed defect class is not a broken
# script — it is the same statement made in three files with three different
# contents, and a harness behavior asserted as settled fact that no current doc
# page covers.
#
# Every assertion below pins a defect that was present at 0.14.0 and is fixed in
# 0.15.0. Each is a grep over the shipped surface, so a later edit that
# reintroduces the drift fails here rather than in a reader's session.
#
# `CHANGELOG.md` is excluded from every content sweep on purpose: it is the
# historical record, it quotes the wording it is retiring, and rewriting a
# shipped entry to satisfy a tripwire is the failure mode this file exists to
# make expensive.
#
# SC2016 is disabled file-wide on purpose. Single-quoted `$ARGUMENTS` strings in
# assertion labels and grep patterns are literal prose/regex under test.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# surface — every shipped instruction file in the plugin, minus the changelog.
# Content lives in markdown and in the evals JSON; both are read by a model, so
# both are in scope.
surface() {
  find "$PLUGIN_ROOT" -type f \( -name '*.md' -o -name '*.json' \) \
    ! -name 'CHANGELOG.md' \
    ! -path '*/.claude-plugin/*' |
    sort
}

# assert_absent <label> <extended-regex>
# Fails listing every hit, because the count is the finding.
assert_absent() {
  local label="$1" pattern="$2" hits
  hits="$(surface | xargs grep -nEI -- "$pattern" 2>/dev/null)"
  if [[ -z "$hits" ]]; then
    pass "$label"
  else
    fail "$label — $(printf '%s\n' "$hits" | wc -l | tr -d ' ') hit(s)"
    printf '%s\n' "$hits" | sed 's|^'"$PLUGIN_ROOT"'/|       |' >&2
  fi
}

# assert_present <label> <file> <extended-regex>
assert_present() {
  local label="$1" file="$2" pattern="$3"
  if [[ -f "$PLUGIN_ROOT/$file" ]] && grep -qEI -- "$pattern" "$PLUGIN_ROOT/$file"; then
    pass "$label"
  else
    fail "$label — no match for /$pattern/ in $file"
  fi
}

# assert_absent_in <label> <file> <extended-regex>
# The label states the absence, so it is the same text either way.
assert_absent_in() {
  local label="$1" file="$2" pattern="$3"
  if grep -qE -- "$pattern" "$PLUGIN_ROOT/$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

printf '# discovery contract test\n\n'

# ---------------------------------------------------------------------------
# 1. The $ARGUMENTS-on-preload mechanism is not asserted anywhere (#2270)
#
# Neither <https://code.claude.com/docs/en/skills> nor
# <https://code.claude.com/docs/en/sub-agents> covers argument substitution on
# the preload path: the skills page scopes `$ARGUMENTS` to "All arguments passed
# when invoking the skill" and the sub-agents page says only that "The full
# content of each listed skill is injected into the subagent's context at
# startup". Silence is not a license to assert the behavior in either
# direction. The operative rule — scope arrives in the dispatch prompt and the
# agent refuses to guess — holds whatever the harness does, so it is what the
# plugin states.
# ---------------------------------------------------------------------------
assert_absent 'no file asserts $ARGUMENTS substitutes to the empty string' \
  'substitutes to the (\*\*)?empty string'
assert_absent 'no file asserts $ARGUMENTS reaches a preloaded body as the empty string' \
  'reaches a preloaded skill body as the empty string'
assert_absent 'no evals entry grades against "empty under preload"' \
  'is empty under preload'
assert_absent 'no file asserts $ARGUMENTS is empty under dispatch' \
  '\$ARGUMENTS. is empty'
assert_absent 'no evals criterion asserts what does or does not reach a preloaded skill' \
  'reaches a preloaded skill'

# ---------------------------------------------------------------------------
# 2. Cross-file pointers resolve from an install root, not from this monorepo
#    (#2269 B-F12)
# ---------------------------------------------------------------------------
assert_absent 'no monorepo-path pointer to the agent definitions' \
  '(^|[^/])plugins/discovery/agents/'

# ---------------------------------------------------------------------------
# 3. The pre-dispatch baseline command is stated once, with both shell forms
#    (#2269 F9). Three sites carried a POSIX-only `mkdir -p … && touch …`;
#    `touch` is not a PowerShell command and `-p` is a parameter error there.
# ---------------------------------------------------------------------------
#    research/SKILL.md carries a second copy so a research parent can dispatch
#    without reading the contract (#4233); section 3b holds the two equal.
# ---------------------------------------------------------------------------
baseline_files="$(surface | xargs grep -lE 'mkdir -p' 2>/dev/null | sed 's|^'"$PLUGIN_ROOT"'/||' | sort | tr '\n' ' ')"
if [[ "$baseline_files" == "reference/parent-contract.md skills/research/SKILL.md " ]]; then
  pass 'the pre-dispatch baseline command lives only in the contract and the research hub'
else
  fail "the pre-dispatch baseline command lives only in the contract and the research hub — found in: $baseline_files"
fi
assert_present 'the baseline home states a PowerShell form' \
  'reference/parent-contract.md' 'New-Item'

# ---------------------------------------------------------------------------
# 3b. The research hub's envelope and baseline copies match the contract (#4233)
#
# Comments and blank lines are dropped before comparing: the contract's block
# carries explore and trace-intent notes the research copy has no use for. The
# hub's one block is the contract's shared block followed by its research block.
# The
# contract's `<explore|research|trace-intent>` baseline name is read as
# `research`.
# ---------------------------------------------------------------------------
# fenced_blocks <file> <fence language> <start heading> [<n>]
# The nth (default first) fenced block of that language between the heading and
# the next `## ` heading, comments and blank lines dropped.
fenced_blocks() {
  awk -v lang="$2" -v start="$3" -v want="${4:-1}" '
    $0 == start { inside = 1; next }
    inside && /^## / { exit }
    inside && $0 == "```" lang { seen++; fence = (seen == want); next }
    fence && $0 == "```" { exit }
    fence { sub(/[[:space:]]+#.*$/, ""); if ($0 !~ /^#/ && $0 != "") print }
  ' "$1"
}
contract="$PLUGIN_ROOT/reference/parent-contract.md"
hub="$PLUGIN_ROOT/skills/research/SKILL.md"
want_envelope="$(fenced_blocks "$contract" text '## The pre-dispatch envelope'; fenced_blocks "$contract" text '## The pre-dispatch envelope' 2)"
hub_envelope_heading='## Pre-dispatch envelope and baseline'
got_envelope="$(fenced_blocks "$hub" text "$hub_envelope_heading")"
if [[ -n "$want_envelope" && "$want_envelope" == "$got_envelope" ]]; then
  pass 'the research hub envelope matches the contract envelope'
else
  fail 'the research hub envelope matches the contract envelope'
  diff <(printf '%s\n' "$want_envelope") <(printf '%s\n' "$got_envelope") | sed 's/^/       /' >&2
fi
for lang in bash powershell; do
  want="$(fenced_blocks "$contract" "$lang" '## The pre-dispatch baseline' | sed 's/<explore|research|trace-intent>/research/g')"
  got="$(fenced_blocks "$hub" "$lang" "$hub_envelope_heading")"
  if [[ -n "$want" && "$want" == "$got" ]]; then
    pass "the research hub $lang baseline matches the contract"
  else
    fail "the research hub $lang baseline matches the contract"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/       /' >&2
  fi
done

# ---------------------------------------------------------------------------
# 4. Truncation and the recovery ladders prescribe ONE outcome (#2272)
#
# Three sites said the parent discards the partial slice *rather than* resuming,
# while both ladders said resume first. Resume-before-discard is the doc-safe
# ordering: <https://code.claude.com/docs/en/sub-agents> — "Resumed subagents
# retain their full conversation history … The subagent picks up exactly where
# it stopped rather than starting fresh."
# ---------------------------------------------------------------------------
assert_absent 'no file prescribes discard-instead-of-resume' \
  'discards the partial slice rather than resuming'
assert_absent 'no file back-references a discard-rather-than-resume rule' \
  'truncation rule discards rather than resumes'
assert_present 'the ordering is stated once, in the parent contract' \
  'reference/parent-contract.md' 'Resume first'

# ---------------------------------------------------------------------------
# 5. The pre-dispatch envelope's memory-root field is delivered (#2268 D-F3)
# ---------------------------------------------------------------------------
assert_present 'the research parent-obligation table carries a Memory root row' \
  'skills/research/context/dispatch.md' '^\| Memory root \|'
assert_present 'the parent contract ships a literal envelope template' \
  'reference/parent-contract.md' 'Memory root:'
assert_present 'the parent contract ships a research Source breadth line' \
  'reference/parent-contract.md' 'Source breadth:'
assert_present 'the research parent-obligation table carries a Source breadth row' \
  'skills/research/context/dispatch.md' '^\| Source breadth \|'

# A breadth token narrows a small question below caller effort, and Budget: has
# one vocabulary mapped to Effort rows.
assert_present 'research argument-hint shows the breadth token' \
  'skills/research/SKILL.md' '^argument-hint: "\[breadth=low\|medium\]'
assert_present 'research SKILL.md states breadth narrows and never widens' \
  'skills/research/SKILL.md' '^\*\*`breadth=` narrows, never widens\.\*\*'
assert_present 'the parent contract defines the Budget: vocabulary once' \
  'reference/parent-contract.md' '^### `Budget:` vocabulary$'
for word in low medium full; do
  assert_present "the Budget: vocabulary maps $word to an Effort row" \
    'reference/parent-contract.md' "^\| \`$word\` \| \`(low|medium|high)\`"
done
assert_present 'the parent contract envelope opens Budget: with the vocabulary' \
  'reference/parent-contract.md' '^Budget: <low\|medium\|full>'

# One topic with many gaps fans out inside Phase 2 when nesting is available;
# the principle alone never fired (#4151).
assert_present 'the discipline file carries the per-gap fan-out recipe' \
  'skills/research/context/discipline.md' '^## Per-gap fan-out \(Phase 2\)$'
assert_present 'research Phase 2 names the per-gap fan-out step' \
  'skills/research/SKILL.md' '^\*\*Fan out per gap when nesting is available\.\*\*'
assert_present 'the researcher body points at the per-gap fan-out' \
  'agents/researcher.md' 'Per-gap fan-out \(Phase 2\)'
assert_present 'research-deep hands shared-claim gaps to the per-gap fan-out' \
  'skills/research-deep/SKILL.md' 'Per-gap fan-out \(Phase 2\)'
for site in agents/researcher.md skills/research/context/discipline.md skills/research/context/phases.md; do
  assert_present "the per-gap fan-out threshold reads two or more numbered gaps in $site" \
    "$site" 'two or more( numbered)?$|two or more numbered gaps'
done
assert_absent 'no fan-out threshold reads 3 or more gaps' \
  '(3|three) or more( numbered( gaps)?)?$|(3|three) or more numbered gaps'

# research-deep points at the Budget: vocabulary and the verifier instead of restating either.
assert_present 'research-deep points Budget: at the parent-contract vocabulary' \
  'skills/research-deep/SKILL.md' 'parent-contract\.md.*"`Budget:` vocabulary"'
assert_present 'research-deep names the verifier, its write-back and the cost skip' \
  'skills/research-deep/SKILL.md' 'discovery:research-verifier`.*`verification:` write-back.*`skipped \(cost\)`'

# ---------------------------------------------------------------------------
# 6. No inert permission grant (#2267 B-F11) + un-run gate is a halt (#2616)
#
# Per <https://code.claude.com/docs/en/skills> (fetched 2026-08-14): in a plugin
# skill, Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in markdown and in Bash
# rules in allowed-tools. That removes the old "token cannot name these
# scripts" leg, but a turn-scoped grant still clears before the post-dispatch
# gate runs, and an interpreter-led Bash(bash …) rule is this repo's
# permission-rule-hygiene anti-pattern 1. So the plugin still ships no grant
# and states the un-run case — including that inline is not an escape hatch
# for it, and that criterion 11 may not be hand-graded.
# ---------------------------------------------------------------------------
#
# setup/SKILL.md is exempt from the first check: its `apply` step 4 renders the
# gate rules an operator adds to user settings (#4233), and the skill body is
# where ${CLAUDE_PLUGIN_ROOT} is substituted, so what lands in settings is the
# absolute root.
# ---------------------------------------------------------------------------
root_rules="$(surface | grep -v '/skills/setup/SKILL.md$' | xargs grep -nEI 'Bash\(\$\{CLAUDE_PLUGIN_ROOT\}' 2>/dev/null)"
if [[ -z "$root_rules" ]]; then
  pass 'no Bash permission rule is written with ${CLAUDE_PLUGIN_ROOT} outside the setup rule list'
else
  fail 'no Bash permission rule is written with ${CLAUDE_PLUGIN_ROOT} outside the setup rule list'
  printf '%s\n' "$root_rules" | sed 's|^'"$PLUGIN_ROOT"'/|       |' >&2
fi
assert_present 'setup renders the gate allow rules from the substituted root' \
  'skills/setup/SKILL.md' '^   Bash\("\$\{CLAUDE_PLUGIN_ROOT\}/scripts/check-dispatch-artifact\.sh" \*\)$'
assert_absent 'no gate allow rule wildcards the version segment' \
  'discovery/\*/scripts/check-'
frontmatter_grants="$(surface | xargs grep -nEI '^allowed-tools:' 2>/dev/null)"
if [[ -z "$frontmatter_grants" ]]; then
  pass 'neither skill declares allowed-tools (the un-run case is stated instead)'
else
  fail 'neither skill declares allowed-tools (the un-run case is stated instead)'
  printf '%s\n' "$frontmatter_grants" >&2
fi
assert_present 'the un-run case is stated' \
  'reference/parent-contract.md' 'could not run'
assert_present 'pre-flight probes gate invocability before routing' \
  'reference/parent-contract.md' 'Pre-flight'
assert_present 'dispatch artifact probe is scoped to the dispatched route' \
  'reference/parent-contract.md' 'Inline explore'
assert_present 'explore does not halt legitimate inline on an unavailable dispatch gate' \
  'skills/explore/SKILL.md' 'does not owe that script'
assert_present 'inline is not an escape hatch for an un-runnable gate' \
  'skills/research/SKILL.md' 'Not an escape-hatch reason'
assert_present 'research keeps coverage fail-closed on the inline path' \
  'skills/research/SKILL.md' 'before an \*\*inline\*\* research run'
assert_present 'criterion 11 fails closed when the script cannot run' \
  'skills/research/SKILL.md' 'could not run at all is the same FAIL'
assert_present 'a non-bash coverage twin is shipped' \
  'scripts/check-coverage-complete.py' 'Python twin'
assert_present 'parent contract names the Python twin' \
  'reference/parent-contract.md' 'check-coverage-complete.py'

# ---------------------------------------------------------------------------
# 7. maxTurns has one owner
#
# The parent contract's harness-facts record names the value and why it stays: a
# checkpoint, not a completion budget. No documented floor exists to test
# adequacy against; the stop-turn reserve below each limit is asserted in the
# envelope section further down.
# ---------------------------------------------------------------------------
turns_of() { grep -m1 -E '^maxTurns:' "$PLUGIN_ROOT/agents/$1.md" | tr -dc '0-9'; }
contract_turns="$(grep -m1 -oE 'Every producing worker definition here \([^)]*\) sets `maxTurns: [0-9]+`' \
  "$PLUGIN_ROOT/reference/parent-contract.md" | grep -oE 'maxTurns: [0-9]+' | tr -dc '0-9')"
verifier_contract_turns="$(grep -m1 -oE 'read-only `research-verifier` sets `maxTurns: [0-9]+`' \
  "$PLUGIN_ROOT/reference/parent-contract.md" | grep -oE 'maxTurns: [0-9]+' | tr -dc '0-9')"
for agent in explorer researcher intent-tracer; do
  agent_turns="$(turns_of "$agent")"
  if [[ -n "$contract_turns" && "$agent_turns" == "$contract_turns" ]]; then
    pass "$agent maxTurns ($agent_turns) equals the parent contract's value ($contract_turns)"
  else
    fail "$agent maxTurns (${agent_turns:-unset}) equals the parent contract's value (${contract_turns:-unset})"
  fi
done
verifier_turns="$(turns_of research-verifier)"
if [[ -n "$verifier_contract_turns" && "$verifier_turns" == "$verifier_contract_turns" ]]; then
  pass "research-verifier maxTurns ($verifier_turns) equals the parent contract's value ($verifier_contract_turns)"
else
  fail "research-verifier maxTurns (${verifier_turns:-unset}) equals the parent contract's value (${verifier_contract_turns:-unset})"
fi
assert_present 'research-verifier pins the verdict tier: model opus' \
  'agents/research-verifier.md' '^model: opus$'
assert_present 'research-verifier pins the verdict tier: effort high' \
  'agents/research-verifier.md' '^effort: high$'

# ---------------------------------------------------------------------------
# 8. Progressive disclosure is not inverted (#2271 D-F4)
#
# research/SKILL.md is preloaded IN FULL into every dispatched run. A hub larger
# than the spoke it delegates to pays that cost on every dispatch. This pins the
# direction, not a byte count.
# ---------------------------------------------------------------------------
hub_words="$(wc -w <"$PLUGIN_ROOT/skills/research/SKILL.md" | tr -d ' ')"
spoke_words="$(wc -w <"$PLUGIN_ROOT/skills/research/context/discipline.md" | tr -d ' ')"
if [[ "$hub_words" -lt "$spoke_words" ]]; then
  pass "research/SKILL.md ($hub_words words) is smaller than context/discipline.md ($spoke_words words)"
else
  fail "research/SKILL.md ($hub_words words) is NOT smaller than context/discipline.md ($spoke_words words)"
fi

# 8b. Compaction re-attaches the first 5,000 tokens. The stand-in is the first
# 20,000 bytes (#4255). Every gate the hub must keep is inside that slice, and
# the same phrase is not waiting in the tail. The worker procedure is the spoke.
# The research slice holds the acceptance and outcome gates, the disciplines they
# grade, the effort ceiling and the topic slot; the pre-dispatch envelope, the
# baseline and the inline conditions follow it, since no gate needs them after a
# dispatch.
assert_in_slice() {
  local label="$1" file="$2" phrase="$3" bytes slice tail
  bytes="$(wc -c <"$PLUGIN_ROOT/$file" | tr -d ' ')"
  slice="$(head -c 20000 "$PLUGIN_ROOT/$file")"
  if [[ "$bytes" -gt 20000 ]]; then
    tail="$(tail -c +20001 "$PLUGIN_ROOT/$file")"
  else
    tail=""
  fi
  if [[ "$slice" == *"$phrase"* && "$tail" != *"$phrase"* ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}
assert_in_slice 'explore outcome gate is inside the re-attach slice' \
  'skills/explore/SKILL.md' '## Outcome gate (before EXPLORE.md handoff)'
assert_in_slice 'explore acceptance gate is inside the re-attach slice' \
  'skills/explore/SKILL.md' 'Post-dispatch acceptance gate'
assert_in_slice 'research outcome gate is inside the re-attach slice' \
  'skills/research/SKILL.md' '## Outcome gate (run before presenting)'
assert_in_slice 'research owner column is inside the re-attach slice' \
  'skills/research/SKILL.md' 'Owner column governs'
assert_in_slice 'research disciplines are inside the re-attach slice' \
  'skills/research/SKILL.md' '## Disciplines'
assert_in_slice 'research last discipline is inside the re-attach slice' \
  'skills/research/SKILL.md' 'Every accepted claim follows from its sources jointly'
assert_in_slice 'research effort ceiling heading is inside the re-attach slice' \
  'skills/research/SKILL.md' '### Effort, source breadth'
assert_in_slice 'research effort ceiling sentence is inside the re-attach slice' \
  'skills/research/SKILL.md' 'The Effort row is the ceiling over discipline 8'
assert_in_slice 'research topic slot is inside the re-attach slice' \
  'skills/research/SKILL.md' 'Research the following topic: $ARGUMENTS'
if grep -q '^## Phase 0:' "$PLUGIN_ROOT/skills/research/context/phases.md" \
  && grep -q '^## Exploration dimensions' "$PLUGIN_ROOT/skills/explore/reference/workflow.md"; then
  pass 'explore and research worker procedures live in the spokes'
else
  fail 'explore and research worker procedures live in the spokes'
fi
# $ARGUMENTS is substituted only in the rendered SKILL.md, never in a spoke read from disk.
# shellcheck disable=SC2016  # literal $ARGUMENTS
if grep -qF 'Explore the following: $ARGUMENTS' "$PLUGIN_ROOT/skills/explore/SKILL.md" \
  && ! grep -qF '$ARGUMENTS' "$PLUGIN_ROOT/skills/explore/reference/workflow.md"; then
  pass 'explore scope substitution stays in SKILL.md'
else
  fail 'explore scope substitution stays in SKILL.md'
fi

# ---------------------------------------------------------------------------
# 9. The research description routes away from research-deep (#2271 D-F9)
#
# research-deep's description already points back at research; the reverse
# boundary was missing, so auto-discovery could route a small lookup into the
# heavier sibling and never the other way.
# ---------------------------------------------------------------------------
assert_present 'the research description carries a boundary against research-deep' \
  'skills/research/SKILL.md' '^description:.*research-deep'
assert_present 'the research description orders single-topic (this skill) before multi-topic routing to research-deep' \
  'skills/research/SKILL.md' '^description:.*right skill for a single topic.*multi-topic.*research-deep'

# ---------------------------------------------------------------------------
# 10. The write boundary is stated once and pointed at (#2270 F6)
# ---------------------------------------------------------------------------
assert_present 'the write boundary names a scratch prefix' \
  'reference/topic-docs.md' 'scratch-'
assert_present 'the write boundary assigns a cleanup owner' \
  'reference/topic-docs.md' '[Cc]leanup'

# The agents must POINT at that statement rather than restate it. Asserting a
# bare link to topic-docs.md would pass vacuously — both agents already linked
# it for the by-value rationale — so this keys on the restatements being gone.
# A non-discriminating assertion is the script-layer form of the self-graded
# gate these skills refuse everywhere else.
assert_absent 'no agent restates the write boundary as a closed two-destination list' \
  'exactly two permitted destinations'
assert_absent 'no agent restates the write boundary as a single destination' \
  'write destination is exactly one place'
for agent in explorer researcher intent-tracer; do
  assert_present "agents/$agent.md defers to the single write boundary" \
    "agents/$agent.md" 'single write boundary'
done

# ---------------------------------------------------------------------------
# 11. Matching token is file-identity, not preload proof (#2895)
#
# The #2374 fallback Reads SKILL.md, so a recovered agent can echo the same
# token a preloaded agent would. Embedding the token in the agent definition
# made that worse: the agent could echo it without seeing the skill at all.
# Provenance is the structured `preload:` field.
# ---------------------------------------------------------------------------
assert_absent_in 'agents/researcher.md does not embed the discipline-liveness token' \
  'agents/researcher.md' 'discovery-research-preload-4c1f9a'
assert_present 'researcher payload contract carries preload: fired|fallback' \
  'agents/researcher.md' 'preload: fired'
assert_present 'researcher early-emission checklist sets preload: beside the token' \
  'agents/researcher.md' '`preload_token` echoed, `preload:` set'
assert_present 'research SKILL.md demotes the token to file-identity' \
  'skills/research/SKILL.md' 'file-identity, \*\*not\*\* proof that preload fired'
assert_present 'research SKILL.md requires the structured preload field' \
  'skills/research/SKILL.md' 'preload: fired \| fallback'
assert_present 'research dispatch contract forbids inferring fired from the token' \
  'skills/research/context/dispatch.md' 'MUST NOT infer'
assert_present 'research evals grade matching-token-is-not-preload-proof' \
  'skills/research/evals/evals.json' 'matching-token-is-file-identity-not-preload-proof'
assert_absent_in 'agents/explorer.md does not embed the preload token' \
  'agents/explorer.md' 'discovery-explore-preload-8e2b7d'
assert_present 'explorer reads the skill body from disk when preload did not deliver it' \
  'agents/explorer.md' 'skills/explore/SKILL\.md'
assert_present 'explorer payload contract carries preload: fired|fallback' \
  'agents/explorer.md' 'preload: fired'
assert_present 'explorer early-emission checklist sets preload: beside the token' \
  'agents/explorer.md' '`preload_token` echoed, `preload:` set'
assert_present 'explorer never reports a token it Read from disk as fired' \
  'agents/explorer.md' 'Never treat a token you found by'
assert_present 'explore SKILL.md demotes the token to file-identity' \
  'skills/explore/SKILL.md' 'file-identity, \*\*not\*\* proof that preload fired'
assert_present 'explore SKILL.md requires the structured preload field' \
  'skills/explore/SKILL.md' 'preload: fired \| fallback'
assert_present 'explore SKILL.md gate treats a missing preload field as out-of-date' \
  'skills/explore/SKILL.md' 'A missing or unrecognized `preload:` field is an out-of-date agent definition'
assert_present 'explore dispatch contract forbids inferring fired from the token' \
  'skills/explore/reference/dispatch.md' 'MUST NOT infer'
assert_present 'explore evals grade matching-token-is-not-preload-proof' \
  'skills/explore/evals/evals.json' 'matching-token-is-file-identity-not-preload-proof'
assert_absent_in 'agents/intent-tracer.md does not embed the discipline-liveness token' \
  'agents/intent-tracer.md' 'discovery-trace-intent-preload-7b3e2d'
assert_present 'intent-tracer payload contract carries preload: fired|fallback' \
  'agents/intent-tracer.md' 'preload: fired'
assert_present 'intent-tracer early-emission checklist sets preload: beside the token' \
  'agents/intent-tracer.md' '`preload_token` echoed, `preload:` set'
assert_present 'trace-intent SKILL.md demotes the token to file-identity' \
  'skills/trace-intent/SKILL.md' 'file-identity, \*\*not\*\* proof that preload fired'
assert_present 'trace-intent SKILL.md requires the structured preload field' \
  'skills/trace-intent/SKILL.md' 'preload: fired \| fallback'
assert_present 'trace-intent dispatch contract forbids inferring fired from the token' \
  'skills/trace-intent/context/dispatch.md' 'MUST NOT infer'
assert_present 'trace-intent evals grade matching-token-is-not-preload-proof' \
  'skills/trace-intent/evals/evals.json' 'matching-token-is-file-identity-not-preload-proof'

# ---------------------------------------------------------------------------
# 12. Joint-inference validity is a verifier-owned gate row
#
# Every other gate row grades provenance or process. A claim can pass all of
# them behind verbatim quotes and still not follow from its sources. Row 12
# asks whether it does, and a verifier grades it off disk, so the sidecar
# header carries what each source measures and each claim's inference and
# qualifiers. Failing claims use the existing vocabulary, a Gap or a Conflicts
# entry; no new status words.
# ---------------------------------------------------------------------------
assert_present 'gate row 12 is owned by the verifier' \
  'skills/research/SKILL.md' '^\| 12 \|.*jointly.*\| \*\*verifier\*\* \|'
assert_present 'gate row 12 routes a FAIL to Phase 2, else a Gap or Conflicts entry' \
  'skills/research/SKILL.md' '^\| 12 \|.*\| Phase 2\..*else a Gap or Conflicts entry \|$'
assert_present 'discipline 15 points at the joint-inference recipe' \
  'skills/research/SKILL.md' '^15\. \*\*.*"Joint-inference check"'
assert_present 'discipline.md carries the joint-inference section' \
  'skills/research/context/discipline.md' '^## Joint-inference check$'
assert_present 'the joint-inference check names the variable sub-test' \
  'skills/research/context/discipline.md' '\*\*Variable check\.\*\*'
assert_present 'the joint-inference check names the population sub-test' \
  'skills/research/context/discipline.md' '\*\*Population check\.\*\*'
assert_present 'the joint-inference check names the hedge-survival sub-test' \
  'skills/research/context/discipline.md' '\*\*Hedge-survival check\.\*\*'
assert_present 'counter-evidence already read is resolved in the artifact' \
  'skills/research/context/discipline.md' '^\*\*Counter-evidence already read'
assert_present 'a failing claim is a Gap or a Conflicts entry' \
  'skills/research/context/discipline.md' 'is a Gap or a Conflicts entry'
assert_present 'the sidecar header carries per-source measures' \
  'skills/research/context/artifact-shape.md' '^ +measures: '
assert_present 'the sidecar header carries per-claim inference' \
  'skills/research/context/artifact-shape.md' '^ +inference: '
assert_present 'the sidecar header carries per-claim qualifiers' \
  'skills/research/context/artifact-shape.md' '^ +qualifiers: '
assert_present 'an improvised header costs criteria 12 and 13 their evidence too' \
  'skills/research/SKILL.md' 'costs criteria 4, 6, 9, 12 and 13 their evidence'
assert_present 'the carry-forward line lists the new header fields' \
  'skills/research/SKILL.md' 'Carry this much into the read:.*measures.*inference.*qualifiers'
assert_present 'the fan-out obligation sends the synthesis to a criterion-12 verifier' \
  'skills/research/context/dispatch.md' '^\*\*The synthesis .*fresh verifier for criterion 12'
assert_present 'the synthesis verifier also checks claims the synthesis adds' \
  'skills/research/context/dispatch.md' 'a claim the synthesis adds'
assert_present 'the SKILL.md fan-out paragraph points at the synthesis criterion-12 check' \
  'skills/research/SKILL.md' '^ +\*\*Fanning out over N topics.*verifier for criterion 12'
assert_present 'the verifier is briefed on rows 4, 7 and 12 by number' \
  'skills/research/context/dispatch.md' 'rows 4, 7 and 12'
assert_present 'the verifier brief overrides the payload criterion string' \
  'skills/research/context/dispatch.md' 'verification_request\.criterion'
assert_present 'gotchas name criterion 12 among the verifier rows' \
  'skills/research/context/gotchas.md' 'Criteria 4, 7 and 12'
assert_present 'evals name criterion 12 among the verifier rows' \
  'skills/research/evals/evals.json' 'criteria 4, 7 or 12'
assert_present 'evals grade a verbatim quote attached to a claim it does not support' \
  'skills/research/evals/evals.json' 'verbatim-quote-is-not-joint-inference'
status_words="$(grep -rnE -- 'CONFLICTED|UNSUPPORTED|CONFIRMED' "$PLUGIN_ROOT/skills/research" 2>/dev/null)"
if [[ -z "$status_words" ]]; then
  pass 'the research skill adds no status vocabulary for a failing claim'
else
  fail 'the research skill adds no status vocabulary for a failing claim'
  printf '%s\n' "$status_words" >&2
fi
assert_absent 'no stale two-row verifier count' \
  '([Cc]riteri(a|on)|rows) 4 (and|or) 7([^,0-9]|$)|[Tt]wo criteria are'
assert_present 'the gate states the Owner column governs over any other enumeration' \
  'skills/research/SKILL.md' 'Owner column governs over any enumeration'
assert_present 'researcher withholds three criteria' \
  'agents/researcher.md' 'Three criteria are'
assert_present 'researcher lists joint inference as a withheld criterion' \
  'agents/researcher.md' '^- the criterion requiring every accepted claim to follow jointly'
assert_present 'researcher verification request names joint-inference validity' \
  'agents/researcher.md' '^  criterion: ".*joint-inference validity'
assert_present 'research-deep lists joint inference among the verifier rows' \
  'skills/research-deep/SKILL.md' 'verifier-owned rows \(independent corroboration, HIGH confidence, joint inference\)'
assert_present 'research-deep points at the synthesis criterion-12 check' \
  'skills/research-deep/SKILL.md' 'synthesized root index also goes to a fresh verifier for criterion 12'
assert_present 'row 12 has one pass bar: the primary measures the variable and population' \
  'skills/research/SKILL.md' "^\| 12 \|.*the claim's primary source measures the claim's variable and population"
assert_present 'a non-measuring corroborator is recorded, not counted' \
  'skills/research/context/discipline.md' 'recorded, not counted toward'
assert_absent 'no evals entry counts the gate criteria' \
  'all [0-9]+ binary criteria'

# ---------------------------------------------------------------------------
# 13. Dispatched agents write early and reserve their last turns
#
# A free-text budget bounds no turn count; a named stop turn leaves the agent
# turns to write before its limit. Each agent states its limit as its own frontmatter number, names a stop turn
# below it, writes an index skeleton marked `Run status: in progress` early, and
# replaces the marker only in its final write. The envelope carries the stop
# turn as a second Budget line. Each agent reads a file once, so turns go to
# gathering rather than re-reading. The research side also names a claim's primary
# source in the sidecar header and the read-only `gh` forms.
# ---------------------------------------------------------------------------

# line_after <file> <extended-regex>: the line directly after the first match.
line_after() {
  awk -v pat="$2" 'found { print; exit } $0 ~ pat { found = 1 }' "$PLUGIN_ROOT/$1"
}

for agent in explorer researcher intent-tracer; do
  file="agents/$agent.md"
  limit="$(turns_of "$agent")"
  assert_present "$file states its limit as its own frontmatter maxTurns ($limit)" \
    "$file" "Your limit is \`maxTurns: ${limit}\`"
  stop="$(grep -m1 -oiE 'stop gathering by turn [0-9]+' "$PLUGIN_ROOT/$file" | tr -dc '0-9')"
  if [[ -n "$stop" && -n "$limit" && "$stop" -gt 0 && "$stop" -lt "$limit" ]]; then
    pass "$file names a stop-gathering turn ($stop) below its limit ($limit)"
  else
    fail "$file names a stop-gathering turn (${stop:-unset}) below its limit (${limit:-unset})"
  fi
  default="$(grep -m1 -oE 'absent, use turn [0-9]+' "$PLUGIN_ROOT/$file" | tr -dc '0-9')"
  if [[ -n "$stop" && "$stop" == "$default" ]]; then
    pass "$file stop turn ($stop) equals its Budget-bullet default ($default)"
  else
    fail "$file stop turn (${stop:-unset}) equals its Budget-bullet default (${default:-unset})"
  fi
  assert_present "$file ignores a Turn budget above its default and notes it" \
    "$file" 'A value above that default is ignored and noted in'
  assert_present "$file writes the index skeleton marked in progress" \
    "$file" 'Run status: in progress'
  assert_present "$file places the marker in the slot after the title heading" \
    "$file" 'first non-blank line after the level-1 title heading'
  assert_present "$file says the gate reads only that slot" \
    "$file" 'gate reads only that slot'
  assert_present "$file replaces the marker in its final write" \
    "$file" 'Run status: complete'
  assert_present "$file reads the envelope's Turn budget line" \
    "$file" 'Turn budget:'
  assert_present "$file keeps a denied path unread by every other tool" \
    "$file" 'is not reached through `Bash`, a script, `Grep`, or any other tool'
done
assert_present "research-verifier states its limit as its own frontmatter maxTurns ($verifier_turns)" \
  'agents/research-verifier.md' "Your limit is \`maxTurns: ${verifier_turns}\`"
verifier_stop="$(grep -m1 -oiE 'stop gathering by turn [0-9]+' "$PLUGIN_ROOT/agents/research-verifier.md" | tr -dc '0-9')"
if [[ -n "$verifier_stop" && -n "$verifier_turns" && "$verifier_stop" -gt 0 && "$verifier_stop" -lt "$verifier_turns" ]]; then
  pass "research-verifier names a stop-gathering turn ($verifier_stop) below its limit ($verifier_turns)"
else
  fail "research-verifier names a stop-gathering turn (${verifier_stop:-unset}) below its limit (${verifier_turns:-unset})"
fi
assert_absent 'no agent says it cannot observe its own turn budget' \
  'cannot observe your own remaining turn'

if [[ "$(line_after reference/parent-contract.md '^Budget: ')" == 'Turn budget: '* ]]; then
  pass 'the parent-contract envelope carries Turn budget: directly under Budget:'
else
  fail 'the parent-contract envelope carries Turn budget: directly under Budget:'
fi
if [[ "$(line_after skills/research-deep/SKILL.md '^ +Budget: ')" =~ ^\ +Turn\ budget:\  ]]; then
  pass 'the research-deep envelope carries Turn budget: directly under Budget:'
else
  fail 'the research-deep envelope carries Turn budget: directly under Budget:'
fi

assert_present 'discipline.md names the read-only gh search forms' \
  'skills/research/context/discipline.md' 'gh search issues'
assert_present 'discipline.md says why the -X and -f forms prompt' \
  'skills/research/context/discipline.md' 'Bash\(gh api -X \*\)'
assert_present 'researcher points at the read-only gh guidance' \
  'agents/researcher.md' 'read-only `gh`'

assert_present 'the sources[] schema carries role: primary' \
  'skills/research/context/artifact-shape.md' '^ +role: primary +# primary \| corroborator'
assert_present 'artifact-shape requires exactly one primary per accepted claim' \
  'skills/research/context/artifact-shape.md' 'exactly one `primary`'
assert_present 'the joint-inference check ties the primary to role: primary' \
  'skills/research/context/discipline.md' '`role: primary`'

assert_absent 'no file says the sub-agents page has no partial-return semantics' \
  'partial-return semantics'
for file in skills/explore/reference/dispatch.md skills/research/context/dispatch.md \
  skills/trace-intent/context/dispatch.md reference/parent-contract.md; do
  assert_present "$file quotes the current partial-marking behavior" \
    "$file" 'returns its output marked as partial'
done
for file in skills/explore/reference/dispatch.md skills/research/context/dispatch.md \
  skills/trace-intent/context/dispatch.md skills/research/context/gotchas.md; do
  assert_present "$file points at the turn-limit harness-facts record" \
    "$file" 'A turn-limit stop returns partial output, and the parent can resume the agent'
  assert_absent_in "$file carries no copy of the turn-limit basis" \
    "$file" 'The partial marking requires'
done
assert_present 'parent-contract holds the turn-limit harness-facts record' \
  'reference/parent-contract.md' '^### A turn-limit stop returns partial output, and the parent can resume the agent$'
assert_present 'the research gotchas describe resume by SendMessage' \
  'skills/research/context/gotchas.md' '`SendMessage` addressed by'

assert_absent 'no file says a half-written artifact set cannot be told apart without the marker' \
  'half-written artifact set cannot be told apart'
for file in reference/parent-contract.md skills/explore/reference/dispatch.md \
  skills/research/context/dispatch.md; do
  assert_present "$file names the in-progress marker where it discusses a partial slice" \
    "$file" 'Run status: in progress'
done
for file in skills/explore/reference/dispatch.md skills/research/context/dispatch.md \
  skills/trace-intent/context/dispatch.md; do
  assert_present "$file places the marker in the slot after the title heading" \
    "$file" 'first non-blank line after the level-1 title heading'
  assert_present "$file says the gate reads only that slot" \
    "$file" 'gate reads only that slot'
done
assert_absent 'no markdown puts a space inside a heading-marker code span (MD038)' \
  '`# `'
assert_absent 'no file says the gate reads the first Run status: line' \
  'first `Run status:` line'
for file in reference/parent-contract.md skills/research-deep/SKILL.md; do
  assert_present "$file bounds the Turn budget placeholder by the default stop turn" \
    "$file" "Turn budget: <.*at or below the agent's default stop turn \(30\)"
done
for file in skills/explore/reference/dispatch.md skills/research/context/dispatch.md \
  skills/trace-intent/context/dispatch.md; do
  assert_present "$file refuses a by-value body still marked in progress" \
    "$file" '`Run status: complete` or no marker; one'
done
assert_absent 'no file narrates the 40-turn incidents as the Turn budget rationale' \
  'bounded nothing: dispatched runs stopped'

# ---------------------------------------------------------------------------
# 14. Sources are gated on era and scenario, not only on quote presence
#
# A quote can sit at its link word for word and come from a source written for
# another product line or major, or one that states only the general mechanism.
# Each source records when it was published and which versions it applies to;
# a script derives current or historical from those fields (criterion 13), and
# the verifier's criterion 12 runs era and scenario checks on every cited
# source. The envelope gains a research-only `Evidence use:` line, so the
# shared count stays six.
# ---------------------------------------------------------------------------
for field in published applies_to standing; do
  assert_present "the sources[] schema carries $field" \
    'skills/research/context/artifact-shape.md' "^ {8}${field}: "
done
assert_present 'each claim carries its target applies_to' \
  'skills/research/context/artifact-shape.md' '^ {4}applies_to: '
assert_present 'the index records evidence_use' \
  'skills/research/context/artifact-shape.md' 'evidence_use: internal \| publish'
assert_present 'gate row 13 is run-owned with a script verdict' \
  'skills/research/SKILL.md' '^\| 13 \|.*check-source-applicability\.py.*\| run, \*\*script verdict\*\* \|'
assert_present 'row 13 applies to inline runs too' \
  'skills/research/SKILL.md' '^\| 13 \|.*inline included'
assert_present 'row 4 counts only current corroborators' \
  'skills/research/SKILL.md' '^\| 4 \|.*`current` corroborators'
assert_present 'row 12 runs era and scenario checks on every cited source' \
  'skills/research/SKILL.md' '^\| 12 \|.*every cited source passes the variable, population, era and scenario checks'
assert_present 'the joint-inference check names the era sub-test' \
  'skills/research/context/discipline.md' '\*\*Era check\.\*\*'
assert_present 'the joint-inference check names the scenario sub-test' \
  'skills/research/context/discipline.md' '\*\*Scenario check\.\*\*'
assert_present 'the checks run on every cited source' \
  'skills/research/context/discipline.md' 'checks on \*\*every cited source\*\*'
assert_present 'discipline.md states the publish tightening' \
  'skills/research/context/discipline.md' '^\*\*Evidence the user will publish\.\*\*'
assert_present 'the recency gate says it dates claims, not sources' \
  'skills/research/context/discipline.md' 'This gate dates claims, not sources'
assert_present 'the parent contract ships an Evidence use line' \
  'reference/parent-contract.md' '^Evidence use: <internal\|publish>$'
assert_present 'the parent contract counts two research-only lines' \
  'reference/parent-contract.md' 'Research adds two more labeled lines'
assert_absent 'no file says research adds only one envelope line' \
  'Research adds one more labeled line'
assert_present 'the research parent-obligation table carries an Evidence use row' \
  'skills/research/context/dispatch.md' '^\| Evidence use \|'
assert_present 'research-deep dispatches with an Evidence use line' \
  'skills/research-deep/SKILL.md' '^ +Evidence use: '
assert_present 'the verifier is briefed on applicability' \
  'skills/research/context/dispatch.md' '^ +\*\*Brief it on applicability too\.\*\*'
assert_present 'the researcher copies evidence use into the index' \
  'agents/researcher.md' 'as `evidence_use:` in your first write'
assert_present 'the researcher payload mirrors the applicability verdict' \
  'agents/researcher.md' '^applicability: pass +# pass \| fail'
for file in skills/research/SKILL.md reference/parent-contract.md \
  skills/research/context/dispatch.md skills/research-deep/SKILL.md agents/researcher.md; do
  assert_present "$file names the source-applicability checker" \
    "$file" 'check-source-applicability\.py|source-applicability'
done
assert_present 'the parent passes its envelope mode to the checker' \
  'skills/research/SKILL.md' '--expect-evidence-use'
if [[ -f "$PLUGIN_ROOT/scripts/check-source-applicability.py" ]]; then
  pass 'the source-applicability checker ships'
else
  fail 'the source-applicability checker ships'
fi

# ---------------------------------------------------------------------------
# The credential read boundary is stated once and pointed at
#
# A researcher's capability probe ran `git credential fill` and captured a live
# token. No frontmatter key can block one shell command, so the rule is
# instruction held in one place, with every agent pointing at it.
# ---------------------------------------------------------------------------
# flat <file>: the file's prose on one line, blockquote markers dropped, so a
# phrase matches wherever the source wraps it.
flat() { sed 's/^> //' "$PLUGIN_ROOT/$1" | tr '\n' ' ' | tr -s ' '; }
cred_heading='^## Credentials stay unread, stated once$'
assert_present 'the parent contract owns the credential read boundary' \
  'reference/parent-contract.md' "$cred_heading"
cred_owners="$(surface | xargs grep -lE -- "$cred_heading" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$cred_owners" -eq 1 ]]; then
  pass 'the credential read boundary has exactly one owner'
else
  fail "the credential read boundary has exactly one owner — $cred_owners files carry the heading"
fi
assert_present 'the credential boundary names git credential fill' \
  'reference/parent-contract.md' '`git credential fill`'
assert_present 'the credential boundary names the operator deny rules' \
  'reference/parent-contract.md' '`Bash\(git credential \*\)`'
for agent in explorer researcher intent-tracer; do
  assert_present "agents/$agent.md points at the credential read boundary" \
    "agents/$agent.md" '"Credentials stay unread, stated once"'
  assert_absent_in "agents/$agent.md does not restate the credential command list" \
    "agents/$agent.md" 'gh auth token'
done

# The rule reaches every agent that holds a shell, not only the three producers:
# the per-gap workers Phase 2 dispatches and the general-purpose sibling verifier
# carry the same Bash pool. The sandbox settings live in the claude-config audit
# reference, so the section points there instead of restating them.
cred_section="$(sed -n '/^## Credentials stay unread, stated once$/,/^## Read each file once/p' \
  "$PLUGIN_ROOT/reference/parent-contract.md" | tr '\n' ' ' | tr -s ' ')"
for scope in 'per-gap workers' 'sibling verifier'; do
  if [[ "$cred_section" == *"$scope"* ]]; then
    pass "the credential section names the $scope"
  else
    fail "the credential section names the $scope"
  fi
done
if [[ "$cred_section" == *allowUnsandboxedCommands* ]]; then
  fail 'the credential section does not restate the sandbox settings'
else
  pass 'the credential section does not restate the sandbox settings'
fi
cred_pointer='verify presence only, never read or print a value; rule and forbidden commands: .*parent-contract\.md, Credentials stay unread'
if [[ "$(flat skills/research/context/discipline.md)" =~ Credentials:\ $cred_pointer ]]; then
  pass "discipline.md's per-gap worker brief carries the credential pointer"
else
  fail "discipline.md's per-gap worker brief carries the credential pointer"
fi
assert_present 'the sibling verifier Posture line carries the credential pointer' \
  'reference/parent-contract.md' "^Posture: .*credentials: $cred_pointer"
if [[ "$(flat agents/research-verifier.md)" == *'credential file is not to be `Read` either'* ]]; then
  pass 'agents/research-verifier.md bars a credential file from Read'
else
  fail 'agents/research-verifier.md bars a credential file from Read'
fi

# ---------------------------------------------------------------------------
# The read-each-file-once rule is stated once and pointed at (#4258)
#
# An explorer run spent a quarter of its turns re-reading files already in its
# context. The rule was pasted into three agents verbatim; it lives in the
# parent contract now, and the agents point at it. The rule's body text must
# not come back into any agent, so a copy cannot drift.
# ---------------------------------------------------------------------------
readonce_heading='^## Read each file once, stated once$'
readonce_phrases=(
  'A file you have already read in this run is still in your context'
  'spends two turns on one read'
  'so your reads stay easy to recognize as reads'
)
readonce_owners="$(grep -cE -- "$readonce_heading" "$PLUGIN_ROOT/reference/parent-contract.md")"
if [[ "$readonce_owners" -eq 1 ]]; then
  pass 'the parent contract carries the read-once heading exactly once'
else
  fail "the parent contract carries the read-once heading exactly once — found $readonce_owners"
fi
readonce_stray="$(surface | grep -v '/reference/parent-contract\.md$' | xargs grep -lE -- "$readonce_heading" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$readonce_stray" -eq 0 ]]; then
  pass 'no other file carries the read-once heading'
else
  fail "no other file carries the read-once heading — $readonce_stray other file(s) do"
fi
contract_flat="$(flat reference/parent-contract.md)"
for phrase in "${readonce_phrases[@]}"; do
  if [[ "$contract_flat" == *"$phrase"* ]]; then
    pass "the parent contract states the read-once rule: $phrase"
  else
    fail "the parent contract states the read-once rule — no match for: $phrase"
  fi
done
for agent in explorer researcher intent-tracer research-verifier; do
  assert_present "agents/$agent.md points at the read-once rule" \
    "agents/$agent.md" '"Read each file once, stated once"'
  agent_flat="$(flat "agents/$agent.md")"
  copied=0
  for phrase in "${readonce_phrases[@]}"; do
    [[ "$agent_flat" == *"$phrase"* ]] && copied=1
  done
  if [[ "$copied" -eq 0 ]]; then
    pass "agents/$agent.md does not restate the read-once rule"
  else
    fail "agents/$agent.md does not restate the read-once rule"
  fi
done

# 15. A direct dispatch of the researcher still learns the gate it owes (#4275)
#
# The post-dispatch gate's steps live in the research skill body. A parent that
# dispatches discovery:researcher without loading that skill never reads them,
# so the agent points at them and its payload names them in band.
# ---------------------------------------------------------------------------
assert_present 'researcher states that whoever dispatched it owes the acceptance gate' \
  'agents/researcher.md' '^## Whoever dispatched you owes the acceptance gate$'
assert_present 'the researcher payload names the gate it is owed' \
  'agents/researcher.md' '^gate_owed: "check-dispatch-artifact\.sh, check-coverage-complete\.sh, check-source-applicability\.py, per skills/research/SKILL\.md Post-dispatch acceptance gate"$'
assert_present 'the parent contract says a direct dispatch owes the gate' \
  'reference/parent-contract.md' 'including a direct dispatch of$'
assert_present 'the research skill still carries the gate the pointer names' \
  'skills/research/SKILL.md' '^\*\*Post-dispatch acceptance gate\. '

# ---------------------------------------------------------------------------
# 16. The research verifier is a named, read-only agent the parent dispatches
#     from a copyable block, and a skip is recorded rather than left pending
#     (#4231)
# ---------------------------------------------------------------------------
verifier='agents/research-verifier.md'
if [[ -f "$PLUGIN_ROOT/$verifier" ]]; then
  pass 'the research verifier agent ships'
  assert_present 'the verifier names an explicit model' "$verifier" '^model: [a-z]'
  assert_present 'the verifier allowlist holds only read tools' \
    "$verifier" '^tools: "Read, Grep, Glob, WebFetch, WebSearch"$'
  assert_present 'the verifier returns the literal verification line' \
    "$verifier" '^verification_line: "verification: pass \(research-verifier, <YYYY-MM-DD>\)"$'
else
  fail 'the research verifier agent ships'
fi
assert_present 'SKILL.md carries a copyable verifier dispatch block' \
  'skills/research/SKILL.md' '^  subagent_type: "discovery:research-verifier",$'
assert_present 'SKILL.md dispatches the verifier at the gate-printed index path' \
  'skills/research/SKILL.md' 'Target: <the index= path the artifact gate printed>'
for file in skills/research/SKILL.md skills/research/context/dispatch.md \
  skills/research/context/artifact-shape.md; do
  assert_present "$file records a cost skip as skipped (cost)" "$file" 'verification: skipped \(cost\)|`skipped \(cost\)`'
done
assert_present 'the researcher writes verification: pending in its first write' \
  'agents/researcher.md' 'first write carries `verification: pending`'
assert_present 'the artifact gate prints the verification value' \
  'scripts/check-dispatch-artifact.sh' "printf 'verification=%s"

# ---------------------------------------------------------------------------
# The sibling verifier is specified once and pointed at
#
# Every payload asks for a verifier, and no agent, prompt, write-back line or
# no-verifier fallback was stated anywhere, so a verified index and one whose
# verifier never ran read the same.
# ---------------------------------------------------------------------------
verifier_heading='^## The sibling verifier, stated once$'
verifier_line='^verification: <pass\|fail\|unverified> \(<worker>, <YYYY-MM-DD>\)$'
assert_present 'the parent contract owns the sibling verifier' \
  'reference/parent-contract.md' "$verifier_heading"
assert_present 'the parent contract states the literal write-back line' \
  'reference/parent-contract.md' "$verifier_line"
assert_present 'the parent contract names the verifier route' \
  'reference/parent-contract.md' '^\*\*Route\.\*\* `explore` and `trace-intent` dispatch a `general-purpose` subagent'
assert_present 'the parent contract states the no-verifier fallback' \
  'reference/parent-contract.md' '`verification: unverified \(none, <YYYY-MM-DD>\)`'
for pair in "heading:$verifier_heading" "write-back line:$verifier_line"; do
  owners="$(surface | xargs grep -lE -- "${pair#*:}" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$owners" -eq 1 ]]; then
    pass "the sibling verifier's ${pair%%:*} is stated exactly once"
  else
    fail "the sibling verifier's ${pair%%:*} is stated exactly once — $owners files carry it"
  fi
done
for file in skills/explore/SKILL.md skills/research/context/dispatch.md \
  skills/trace-intent/context/dispatch.md; do
  assert_present "$file points at the sibling verifier" \
    "$file" '"The sibling verifier, stated once"'
done

# One table owns the verification: value set (#4274, #4231). skipped (cost) is
# the parent choosing not to pay, unverified (none, <date>) is it being unable
# to dispatch, and the table is the one place that says so. artifact-shape.md
# keeps a one-line list, which must match the table's first column.
values_heading='^### The `verification:` values$'
assert_present 'the parent contract owns the verification: values table' \
  'reference/parent-contract.md' "$values_heading"
values_owners="$(surface | xargs grep -lE -- "$values_heading" 2>/dev/null | wc -l | tr -d ' ')"
values_count="$(grep -cE -- "$values_heading" "$PLUGIN_ROOT/reference/parent-contract.md")"
if [[ "$values_owners" -eq 1 && "$values_count" -eq 1 ]]; then
  pass 'the verification: values heading exists exactly once'
else
  fail "the verification: values heading exists exactly once — $values_owners files carry it, $values_count times in the parent contract"
fi
values_table="$(awk '/^### The `verification:` values$/ {on=1; next} on && /^#/ {exit} on' \
  "$PLUGIN_ROOT/reference/parent-contract.md")"
for value in 'pass (research-verifier, <date>)' \
  'fail rows <n>[,<n>…] (research-verifier, <date>)' \
  'skipped (cost)' 'unverified (none, <date>)' 'pending'; do
  if [[ "$values_table" == *"| \`$value\` |"* ]]; then
    pass "the values table has a row for $value"
  else
    fail "the values table has a row for $value"
  fi
  if grep -qF -- "\`$value\`" "$PLUGIN_ROOT/skills/research/context/artifact-shape.md"; then
    pass "artifact-shape.md lists $value as the table does"
  else
    fail "artifact-shape.md lists $value as the table does"
  fi
done

# verdict: is the report contract's run outcome (complete | partial | stopped),
# so the explore and trace-intent verifier's pass or fail line is result:.
assert_absent 'no file has a verifier return pass or fail on a verdict: line' \
  'verdict: (pass|fail)'
assert_present 'the explore and trace-intent verifier returns result: pass or result: fail' \
  'reference/parent-contract.md' '^Return: first line `result: pass` or `result: fail`'

# The intro lists what the contract owns without counting it, so adding a
# statement cannot stale a number.
intro_flat="$(sed '/^## The pre-dispatch envelope$/q' "$PLUGIN_ROOT/reference/parent-contract.md" | tr '\n' ' ')"
if grep -qiE '(^|[^[:alpha:]])(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+) statements' <<<"$intro_flat"; then
  fail 'the parent contract intro spells out no count before statements'
else
  pass 'the parent contract intro spells out no count before statements'
fi

# ---------------------------------------------------------------------------
# 17. References follow the content that moved into the spokes
# ---------------------------------------------------------------------------
assert_present 'blindspot names the explore workflow spoke' \
  'skills/blindspot/SKILL.md' 'skills/explore/reference/workflow\.md'
assert_absent_in 'blindspot does not send the moved dimensions to the explore hub' \
  'skills/blindspot/SKILL.md' 'skills/explore/SKILL\.md'
assert_present 'the researcher names the phases spoke' \
  'agents/researcher.md' 'skills/research/context/phases\.md'
for file in skills/research/SKILL.md skills/blindspot/SKILL.md; do
  assert_present "$file carries a Next section" "$file" '^## Next$'
done

# ---------------------------------------------------------------------------
# 18. Each agent carries one final-message shape
#
# `discovery:report` is a second return shape. An agent that preloads it carries
# that core beside its own `Return exactly this` block, and the parent parses
# the agent's own block, so the preload adds a contradiction and no contract.
# A bare `report` entry resolves inside this plugin, so it counts too.
# ---------------------------------------------------------------------------
for agent in explorer researcher intent-tracer research-verifier; do
  file="agents/$agent.md"
  if awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$PLUGIN_ROOT/$file" |
    grep -qE "^skills:.*report|^[[:space:]]+-[[:space:]]*[\"']?(discovery:)?report[\"']?[[:space:]]*$"; then
    fail "$file does not preload the report return contract"
  else
    pass "$file does not preload the report return contract"
  fi
  sections="$(grep -cE '^## Return exactly this' "$PLUGIN_ROOT/$file")"
  if [[ "$sections" -eq 1 ]]; then
    pass "$file has exactly one Return exactly this section"
  else
    fail "$file has exactly one Return exactly this section — found $sections"
  fi
done

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'All contract assertions passed.\n'
  exit 0
fi
printf '%d contract assertion(s) failed.\n' "$fails" >&2
exit 1
