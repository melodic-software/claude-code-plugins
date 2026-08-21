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

printf '# discovery contract test\n\n'

# ---------------------------------------------------------------------------
# 1. The $ARGUMENTS-on-preload mechanism is not asserted anywhere (#2270)
#
# Neither <https://code.claude.com/docs/en/skills> nor
# <https://code.claude.com/docs/en/sub-agents> covers argument substitution on
# the preload path: the skills page scopes `$ARGUMENTS` to "All arguments passed
# when invoking the skill" and the sub-agents page says only that "The full
# content of each listed skill is injected into the subagent's context at
# startup". Silence is not a licence to assert the behavior in either
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
baseline_files="$(surface | xargs grep -lE 'mkdir -p' 2>/dev/null | sed 's|^'"$PLUGIN_ROOT"'/||' | sort)"
if [[ "$baseline_files" == "reference/parent-contract.md" ]]; then
  pass 'the pre-dispatch baseline command has exactly one home'
else
  fail "the pre-dispatch baseline command has exactly one home — found in: $(printf '%s' "$baseline_files" | tr '\n' ' ')"
fi
assert_present 'the baseline home states a PowerShell form' \
  'reference/parent-contract.md' 'New-Item'

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
assert_absent 'no Bash permission rule is written with ${CLAUDE_PLUGIN_ROOT}' \
  'Bash\(\$\{CLAUDE_PLUGIN_ROOT\}'
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
# 7. maxTurns parity (#2267 B-F6)
#
# The explorer is the read-heavier workload and carried the smaller budget, with
# no stated reason. Parity is the claim; nothing here asserts a cause for any
# past run.
# ---------------------------------------------------------------------------
turns_of() { grep -m1 -E '^maxTurns:' "$PLUGIN_ROOT/agents/$1.md" | tr -dc '0-9'; }
explorer_turns="$(turns_of explorer)"
researcher_turns="$(turns_of researcher)"
if [[ -n "$explorer_turns" && -n "$researcher_turns" && "$explorer_turns" -ge "$researcher_turns" ]]; then
  pass "explorer maxTurns ($explorer_turns) >= researcher maxTurns ($researcher_turns)"
else
  fail "explorer maxTurns (${explorer_turns:-unset}) >= researcher maxTurns (${researcher_turns:-unset})"
fi

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
if grep -qE 'discovery-research-preload-4c1f9a' "$PLUGIN_ROOT/agents/researcher.md"; then
  fail 'agents/researcher.md does not embed the discipline-liveness token'
else
  pass 'agents/researcher.md does not embed the discipline-liveness token'
fi
assert_present 'researcher payload contract carries preload: fired|fallback' \
  'agents/researcher.md' 'preload: fired'
assert_present 'research SKILL.md demotes the token to file-identity' \
  'skills/research/SKILL.md' 'file-identity, \*\*not\*\* proof that preload fired'
assert_present 'research SKILL.md requires the structured preload field' \
  'skills/research/SKILL.md' 'preload: fired \| fallback'
assert_present 'research dispatch contract forbids inferring fired from the token' \
  'skills/research/context/dispatch.md' 'MUST NOT infer'
assert_present 'research evals grade matching-token-is-not-preload-proof' \
  'skills/research/evals/evals.json' 'matching-token-is-file-identity-not-preload-proof'

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'All contract assertions passed.\n'
  exit 0
fi
printf '%d contract assertion(s) failed.\n' "$fails" >&2
exit 1
