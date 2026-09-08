# next-skill-suggestions

## Brief

> **Revised 2026-09-07 (plan stress-test, before approval).** Three changes to the interview's
> Brief, each driven by convention text read during planning: (1) the `## Next` register is
> pure mention, bare tokens with no installed-ness gate and no `else` clause, because the
> invocation-mode convention lists "fall back to" among operative verbs and classes a
> situation-to-sibling coverage map as a mention that needs no gate; (2) the advisory WARN is
> dropped from this PR, because it would fire on 44 stage-bearing skills after merge and the
> same convention records that a check firing on most of the fleet is how check output gets
> ignored; (3) `docs-hygiene:rename-references` leaves scope, because it already routes onward
> in its `## Integration with workflow` table. Scope is now 29 skills across 18 plugins.

### TLDR

- Add a `## Next` section to 29 skills (Tier A 8, Tier B 21, listed in the interview's
  `CANDIDATES.md`) that today end with no successor named.
- The section is a plain mention of hardcoded successor skills: bare `/plugin:skill` tokens,
  no gate, no fallback clause. Never a Skill-tool chain, never a runtime lookup, never
  `/session-flow:show-options` or `/session-flow:workflow`.
- Two allowed shapes: one bare line, or two to four outcome bullets when the successor depends
  on the run's result.
- Four lines of authoring discipline in the existing skill-body rule so the successor graph
  stays current. No CI addition, no lint addition.

### Goal

A human running any of the 29 skills sees, right after the work, which skill normally runs
next, named specifically, at zero listing-budget cost and zero tool calls, in the bare-token
shape `performance:goal`, `performance:snapshot`, and `performance:target` already use. The
staged spine already routes; this closes the gap in the skills that forgot to.

### Constraints

- Mention only. The invocation-mode convention's chaining section separates a mention from an
  operative chain; every `## Next` line is a coverage map from situation to sibling. No
  "invoke", "run", "hand off to", "route to", "fall back to", no imperative addressed to the
  model, no installed-ness gate, no `else` clause.
- No dynamic lookup. Router skills are REJECTED fleet-wide (`docs/conventions/invocation-mode/`),
  and ADR 0016 defers the Stop/TaskCompleted hook. Neither is reopened; a hardcoded body
  section is neither a router skill nor a hook.
- `session-flow:workflow` stays the owner of stage routing. A `## Next` states the typical
  successor; when the two disagree, the workflow skill's ladder wins. Stated once in the rule.
- Section placement: immediately before `## Gotchas` when the file has one, else before the
  file's last H2. This is the `performance:*` order (boundary, then Next, then Gotchas).
- Bodies state the current rule only (`.claude/rules/skill-bodies-state-current-rules.md`). No
  "added because the audit found" narration in any `## Next`.
- Every `## Next` bullet is descriptive of where work lands, never an instruction to the
  executing model. This holds in unattended runs too: a skill body cannot detect that it is
  unattended, so the text must be safe to read in either mode.
- AFK drivers (`work-items:work-loop`, `work-items:work`, `source-control:babysit-loop`,
  `source-control:babysit-prs`, `implementation:implement-dispatch`,
  `session-flow:continue-in-background`) and `plugins/autonomy/hooks/lane-stop-gate.sh` are
  untouched.
- No new CI job, workflow, script, or lint check.
- One worktree, one feature branch, one PR. Every touched plugin bumps its patch version and
  carries a CHANGELOG entry. Workers read the current version from `plugin.json` at edit time.
- `playbooks:skill-authoring` is vendored; its heading is `## Next (Melodic Software addition)`
  to match every other local H2 in that file.
- PR body follows `.claude/rules/pr-body-contract.md`; the PR opens as a draft per `AGENTS.md`.

### Acceptance criteria

- Each of the 29 target skills carries a `## Next` H2 (or `## Next (Melodic Software
  addition)` for playbooks) placed immediately before `## Gotchas`, or before the file's last
  H2 when the file has no `## Gotchas`.
- Every `/plugin:skill` token inside a `## Next` section resolves to an existing
  `plugins/<plugin>/skills/<skill>/SKILL.md` on the branch. Pasteable check, also carried in
  the PR's `## Verification`:
  `for f in $(git diff --name-only origin/main -- 'plugins/*/skills/*/SKILL.md'); do awk '/^## Next/{f=1;next} /^## /{f=0} f' "$f" | grep -oE '/[a-z0-9-]+:[a-z0-9-]+' | while read t; do p=${t#/}; test -f "plugins/${p%%:*}/skills/${p#*:}/SKILL.md" || echo "DEAD $t in $f"; done; done`
  prints nothing.
- A `## Next` section is either one line holding one token, or two to four bullets of the
  form `- <outcome>: /plugin:skill.` Never more than four bullets.
- No `## Next` section contains "Skill tool", "invoke", "run", "hand off", "route to", "fall
  back", "if that plugin is installed", or "else". Pasteable check:
  `for f in $(git diff --name-only origin/main -- 'plugins/*/skills/*/SKILL.md'); do awk '/^## Next/{f=1;next} /^## /{f=0} f' "$f" | grep -inE 'skill tool|invoke|\brun\b|hand off|route to|fall back|is installed|\belse\b' && echo "OPERATIVE in $f"; done`
  prints nothing.
- `.claude/rules/skill-bodies-state-current-rules.md` carries a `## Successor sections` H2
  with four bullets: new skill writes its `## Next` and edits the predecessor whose `## Next`
  should now name it; rename runs `/docs-hygiene:rename-references audit`; removal greps the
  token and edits each `## Next` that carried it; `session-flow:workflow` owns stage routing
  when a `## Next` and the router disagree. Its frontmatter `description` names successor
  sections.
- IF a `## Next` token names a skill that does not exist on the branch, THEN the PR review
  reports it and the PR does not merge until fixed. Enforced by the reviewer running the
  token check above from the PR's `## Verification` section, not by CI.
- Each touched plugin's `plugin.json` version is bumped and its `CHANGELOG.md` gains a matching
  `## [<version>]` entry: `bash scripts/check-changelog-parity.sh --check-bump origin/main`
  exits 0.
- `bash scripts/check-changed-skills.sh origin/main` exits 0 (runs `check-skill.sh
  --require-evals` over every touched skill).
- `bash scripts/affected-tests.sh --run` exits 0.

### Captured assumptions

- The 29-skill list (Tier A + Tier B minus `rename-references`) is the scope. Revisit if
  another target turns out to already carry a routing section the census missed;
  `source-control:commit`'s `## Composition policy` was checked and states ownership, not a
  successor, so it stays.
- The specific successor per skill is chosen from the skill's own boundary text and its
  siblings' routing tables, drafted before approval and read in full by the main session
  before commit.
- `review:audit-enforceability` (198 lines) and `playbooks:skill-authoring` (196 lines) use the
  one-line shape. A section is four lines minimum, so `audit-enforceability` lands at 202 and
  carries the advisory soft-cap WARN; accepted, since trimming unrelated body text to dodge a
  WARN is outside this change's scope.
- CHANGELOG conflict exposure is accepted: `source-control` sees roughly four CHANGELOG commits
  a day and `work-items`, `claude-config`, `knowledge`, `docs-hygiene` are close behind. Cost is
  a rebase before ready-for-review; versions are re-read from `plugin.json` at that point.
- State-driven acceptance case: none applies. Unwanted-behaviour case captured above.

### Out-of-scope

- Any operative chain to `/session-flow:show-options` or `/session-flow:workflow`.
- Extending `lane-stop-gate.sh` or any AFK driver. The AFK explore recommended placing any
  terminal step at the lane's stop rather than in skill bodies; the interview settled that no
  AFK gap exists (drivers own sequencing), so nothing is added at either place.
- The advisory WARN in `skill-quality:check` for stage-bearing skills missing `## Next`.
  Dropped because 44 stage-bearing skills would still WARN after this PR (29 even with a
  widened heading regex). Tracked as a follow-up work item after merge, to land once the
  residual set is small enough that the WARN is signal.
- A CI check that resolves `/plugin:skill` tokens repo-wide.
- Rewriting the 59 existing routing tables or the staged-spine skills.
- Amending ADR 0016. Nothing new cites `show-options`, so its text stays as is.
- Pocock-lineage skills already routing or terminal by design (25 of 28).
- `docs-hygiene:rename-references`: already routes via `## Integration with workflow`.

### Deferred questions

- None.

## Plan

### Goal

Every one of the 29 target skills names its successor in a `## Next` section a human reads after
the work, bare tokens in the `performance:*` shape, at zero listing-budget cost. The authoring
rule tells the next author how to keep the graph current and who owns stage routing.

### Standards grounding

Loaded: `docs/conventions/invocation-mode/README.md` "Cross-skill invocation phrasing" (mention
vs operative chain, operative-verb list, coverage-map exemption) and "Router-skill verdict";
`docs/conventions/seam-phrasing/README.md` (gate belongs where an invocation is instructed;
descriptive ownership needs none); `.claude/rules/skill-bodies-state-current-rules.md`;
`.claude/rules/pr-body-contract.md`; `AGENTS.md`; `scripts/check-changed-skills.sh` and
`scripts/check-changelog-parity.sh` headers (the two gates that judge SKILL.md and version
changes, which `affected-tests.sh` does not select for `*.md`/`*.json`). No `docs/standards/`
index exists; grounding is inferred from the conventions tree (ladder rung 4).

### Approach

The per-skill successor text is drafted and token-verified in the memory slice
(`.work/next-skill-suggestions/successors.md`, 29 blocks, session-local and never committed). The
plan applies it, adds the rule, and verifies with tracked, pasteable commands so a reviewer on
any checkout can rerun them.

### Phase 1: Authoring rule [DONE]

File: `.claude/rules/skill-bodies-state-current-rules.md`. Append one H2 `## Successor sections`
with four bullets (new skill: write `## Next`, edit the predecessor whose `## Next` should now
name it; rename: `/docs-hygiene:rename-references audit`; removal: grep the token, edit each
`## Next` that carried it; `session-flow:workflow` owns stage routing when a `## Next` and the
router disagree). Extend the frontmatter `description` with "and name their successor in a
`## Next` section" so the rule's own summary covers the new H2. Present tense, no history.

**Sanity Check:** `grep -c '^## Successor sections' .claude/rules/skill-bodies-state-current-rules.md`
returns 1; `grep -c 'rename-references' .claude/rules/skill-bodies-state-current-rules.md`
returns 1; `grep -c 'session-flow:workflow' .claude/rules/skill-bodies-state-current-rules.md`
returns 1; `head -3 .claude/rules/skill-bodies-state-current-rules.md | grep -c 'Next'` returns 1.

### Phase 2: Insert `## Next` in 29 skills, bump 18 plugins [DONE]

Source of truth: `.work/next-skill-suggestions/successors.md` (memory slice). Each block names
the H2 to insert before and the exact section text.

Per skill: insert the block's fenced section immediately before the named H2, with one blank line
on each side. Per plugin: read the current `version` from `.claude-plugin/plugin.json`, bump the
patch, and add a `## [<new>]` / `### Added` entry at the top of `CHANGELOG.md` naming the skills
that gained a `## Next` section.

File inventory (29 SKILL.md + 18 plugin.json + 18 CHANGELOG.md = 65 files):

| Plugin | Skills |
|---|---|
| code-metrics | audit-complexity, audit-coverage, audit-duplication, audit-size, audit-type-debt, setup |
| docs-hygiene | audit-noise, audit-progressive-disclosure |
| source-control | commit, resolve-conflicts |
| prototype | explore-directions, pressure-test |
| event-storming | methodology, simulation |
| claude-config | audit-instructions, audit-permission-grants |
| architecture | map-landscape, setup |
| work-items | triage |
| testing | audit |
| review | audit-enforceability |
| playbooks | skill-authoring |
| performance | verify |
| overengineering | realign |
| mutation-testing | audit |
| knowledge | docpage-digest |
| evals | design |
| discovery | trace-intent |
| code-tidying | audit-comment-residue |

**Sanity Check:** `python .work/next-skill-suggestions/verify-targets.py` (session-local) prints
a first column of `1` for 28 rows and `2` for `discovery:trace-intent` (its dispatch
`## Routing` H2 predates this change); the tracked equivalent is
`git diff --name-only origin/main -- 'plugins/*/skills/*/SKILL.md' | xargs grep -lE '^## Next' | wc -l`
printing 29.
**Sanity Check:** the token-resolution one-liner in the Brief prints nothing.
**Sanity Check:** the operative-phrasing one-liner in the Brief prints nothing.
**Sanity Check:** `wc -l plugins/playbooks/skills/skill-authoring/SKILL.md` prints 200 or less;
`wc -l plugins/review/skills/audit-enforceability/SKILL.md` prints 202 (accepted soft-cap WARN).
**Sanity Check:** `git diff --stat origin/main | grep -c 'plugin.json'` prints 18 and
`git diff --stat origin/main | grep -c 'CHANGELOG.md'` prints 18.
**Sanity Check:** `bash scripts/check-changed-skills.sh origin/main` exits 0 and
`bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 3: Verify and open the draft PR [DOING]

1. `bash scripts/affected-tests.sh --run` exits 0.
2. `npx markdownlint-cli2 <the 29 SKILL.md files> .claude/rules/skill-bodies-state-current-rules.md`
   exits 0.
3. Commit per phase (two commits), push, open a **draft** PR with body per
   `.claude/rules/pr-body-contract.md` opening `Closes #3947`; `## Verification` carries the two
   Brief one-liners and their empty output plus the two gate commands and their exit codes.
4. File the follow-up work item for the dropped WARN (filed as #3959), naming the
   residual stage-bearing set (measured: 44 with `^## Next` only, 29 with a widened regex).

**Sanity Check:** `gh pr view --json isDraft -q .isDraft` prints `true`;
`gh pr view --json body -q .body | grep -c '^Closes #3947'` prints 1.

### Test strategy

No executable behavior changes. Verification is the pasteable one-liners in the Brief plus the two
repo gates (`check-changed-skills.sh`, `check-changelog-parity.sh --check-bump`) and
`affected-tests.sh --run`. No test boundary is introduced.

### Alternatives considered

- **Gate + fallback on every cross-plugin token** (the interview's Q7 shape). Rejected: "fall
  back to" is on the operative-verb list, so the shape cannot be a mention and a gate at once.
  Switch condition: the convention reclassifies conditional fallbacks as mentions.
- **Ship the advisory WARN now with a widened heading regex.** Rejected: 29 residual WARNs on
  merge day. Switch condition: the residual set drops under roughly ten.
- **Split into three PRs by plugin group** to cut CHANGELOG conflicts. Rejected: the user asked
  for one PR. Switch condition: the rebase before ready-for-review conflicts on more than five
  plugins.
- **Route every `## Next` to `/session-flow:workflow`.** Rejected at interview (Q2). Switch
  condition: none within this PR.
- **Place any terminal step at the AFK lane's stop** (the AFK explore's recommendation).
  Rejected: the interview found no AFK gap. Switch condition: a work-loop cycle is observed
  acting on a `## Next` line.

### Risks and mitigations

- **A model executes a mention as a chain in an unattended run.** Mitigation: every bullet is
  descriptive of where work lands, the triage block names the operator's queue as a place not a
  step, and no `## Next` names a merge-capable skill. Residual: accepted; the same exposure
  already exists in every "Related skills" list in the fleet.
- **A successor drifts after a rename.** Mitigation: Phase 1 rule plus the existing
  `rename-references` sweep. Residual: accepted at interview (no CI check).
- **CHANGELOG and `plugin.json` conflicts on hot plugins.** Mitigation: open the PR the same
  session; rebase before ready-for-review; versions re-read at edit and rebase time.

## Blast radius

MEDIUM. 29 skill bodies the model reads at invocation, one always-on rules file for every
skill-body edit. Trigger matched: "new agent-instruction rules". No hook, no CI, no lint, no
runtime behavior change.

## Stress-test summary

Two fresh-context passes ran on the first draft: a plan reviewer (3 CRITICAL, 7 IMPORTANT, 6
SUGGESTION) and `/planning:devils-advocate` (1 CRITICAL, 3 HIGH, 4 MEDIUM, 4 LOW). Every
confirmed finding is folded in above: register changed to pure mention; WARN dropped
(measured residual 44 / 29); `rename-references` dropped; placement rule restated to match
`performance:*`; broken `grep -l -A6` sanity check replaced with awk section extraction; the two
real gates (`check-changed-skills.sh`, `check-changelog-parity.sh --check-bump`) named; versions
read from `plugin.json` not the draft; playbooks heading suffixed; near-cap skills forced to the
one-line shape; `session-flow:workflow` ownership sentence added to the rule; rule description
extended; token check made pasteable so a reviewer on any checkout can run it. Findings not
adopted: split into multiple PRs (user asked for one; recorded as an alternative with a switch
condition); derive the stage list from `cheatsheet-config.mjs` (moot, WARN dropped).

## Execution shape

Phase 1 is three lines of judgment in a rules file: main session. Phase 2 is 65 mechanical,
file-disjoint edits from a verified draft: four Sonnet workers in one wave, each owning a plugin
group, then a main-session read of every inserted section before commit. Phase 3 main session.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | four bullets and a description edit in a rules file |
| 2 | 4 sub-agent workers (Sonnet), one wave | 65 mechanical edits from a verified source; disjoint files per plugin |
| 3 | main session | verification, PR, follow-up item |

Worker scope fences (Phase 2):

| Worker | ALLOWED | FORBIDDEN |
|---|---|---|
| A | `plugins/code-metrics/**`, `plugins/docs-hygiene/**` | everything else, `PLAN.md` |
| B | `plugins/source-control/**`, `plugins/prototype/**`, `plugins/event-storming/**`, `plugins/claude-config/**`, `plugins/architecture/**` | everything else, `PLAN.md` |
| C | `plugins/work-items/**`, `plugins/testing/**`, `plugins/review/**`, `plugins/playbooks/**`, `plugins/performance/**` | everything else, `PLAN.md` |
| D | `plugins/overengineering/**`, `plugins/mutation-testing/**`, `plugins/knowledge/**`, `plugins/evals/**`, `plugins/discovery/**`, `plugins/code-tidying/**` | everything else, `PLAN.md` |

Cost: 4 Sonnet workers versus one sequential pass; each worker reads 4-8 files and writes 6-18.
Sequential fallback: the main session applies `successors.md` plugin by plugin in the same order.

## Open questions

None at approval time. Three Brief changes are surfaced for the user in the approval message.

## Handoff to implementation

### User-approval gates

- None beyond plan approval. No `[FALLBACK]` decisions.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Phase order 1 → 2 → 3; Phase 2 fanned out to four Sonnet workers by plugin
  group with the fences above; workers report, never commit; main session commits per phase.
- [EXEC-SHAPE] Placement rule: before `## Gotchas` when present, else before the last H2.
- [EXEC-SHAPE] One-line shape forced on the two skills within four lines of the soft cap.

### Mechanical work

- Commit boundaries: one commit per phase (`docs(rules): ...`, `docs(skills): ...`),
  Conventional Commits subject, trailer per session attribution.
- Verification checkpoint after Phase 2: all six Phase 2 sanity checks before the commit.
- PR opens as draft; flip to ready after `affected-tests.sh --run` is green on the pushed head.
