# web-writing-conciseness

Topic slug: `web-writing-conciseness`. Interview ledger and discovery artifacts:
`.work/web-writing-conciseness/` (memory tier, not committed). Status: Brief LOCKED 2026-09-05
after three interview rounds (18 questions, all resolved, user-confirmed). Ready for
`/planning:plan`.

## Brief

### TLDR

- A new small plugin (`writing`, category `presentation`) with one dual-mode skill,
  `writing:concise`: invoked bare it sets a standing posture for the session; given any target it
  reshapes that text for a scanning human reader. Plus one doctrine reference file.
- Doctrine derived from NN/g (concise, scannable, objective), GOV.UK, US plain language, Google,
  Microsoft, and BLUF, paraphrased with drift stamps; NN/g is never vendored.
- Reciprocal routing: ai-slop, docs-hygiene:write-for-humans, and discipline:tighten-your-output
  Boundaries point at the new skill for reader-facing prose; write-for-agents gets a pointer to
  the universal brevity rules.
- Proactive reach by presence-gated pointers at the composition sites (work-items templates,
  pull-request create 2.4.1, bugs:write, planning:prd); no hook.
- Judgment-only V1 with before/after word counts; thresholds shipped as a labelled fallback.

### Goal

The doctrine rests on one reader model: the reader scans and takes away a fraction of what was
written. Four properties follow, and the skill enforces all four. The point comes first. No more
words than the meaning needs. Structure survives scanning. Tone stays factual. Conciseness leads
the name because it was the largest single lever in the evidence, but a wall of text usually fails
all four at once, and fixing one alone does not make it readable.

Agents stop posting walls of text that product owners and executives cannot read. Any prose an
agent writes for a human reader in an external system (Jira, ADO, Linear, GitHub PR bodies and
comments, status updates) or in repo human docs (READMEs, changelogs) leads with the bottom line,
carries about half the words a first draft would, and is scannable, without dropping any
decision, number, ask, error, or warning. The same capability cleans up text that has already
been posted, on request.

### Constraints

- No new always-on hook: the marketplace hook budget is over ceiling and its rule 2 never relaxes.
- NN/g articles are copyrighted with terms that forbid reposting; only brief quotes with credit.
  Paraphrase with a four-part drift stamp per `docs/conventions/upstream-drift/README.md`.
- The ai-slop catalog is a closed CC BY-SA corpus; new material cannot be added to it.
- Cross-plugin references cite `/plugin:skill` by name with presence gating, never a sibling's
  `context/` or `reference/` file (encapsulation rule).
- Every touched plugin needs a version bump and CHANGELOG entry; every new or modified SKILL.md
  needs `evals/evals.json` (`--require-evals`).
- A rewrite must never break the pr-issue-linkage contract (closing keyword line plus the four
  required sections) when the target is a PR body.
- Draft PR #3766 (code-metrics) edits `.claude-plugin/marketplace.json`,
  `scripts/skill-leaf-name-registry.txt`, `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md`; rebase
  after it merges or expect list conflicts.
- One feature branch and one draft PR carry the whole change (new plugin, reciprocal Boundary
  edits, composition-site pointers, and every plugin version bump); no split.
- No second skill: the standing posture and the targeted rewrite are two modes of one skill.

### Acceptance criteria

- A `plugins/writing/` directory with `plugin.json`, README, CHANGELOG, `skills/concise/SKILL.md`,
  a `reference/` doctrine file, and `evals/evals.json`; `skill-quality:check` and
  `scripts/check-skill-leaf-names.sh --check` pass. The skill's description names all four
  properties in its first line, so the one-word name never has to carry them alone, and routes
  away from `adhd:clarify`, `docs-hygiene:compress`, and `discipline:tighten-your-output` by name.
- Inputs are universal: the skill accepts any text or reference the agent can resolve with the
  tools it has (pasted text, a file, a URL, a PR, a ticket key) and does not enumerate input types.
- Reader, destination, and completeness floor are inferred from principles stated in the doctrine
  (who reads it, where it lands, what must survive, including any structural contract the
  destination imposes such as a PR body's required sections); there is no fixed profile table, and
  any examples are illustrations.
- The doctrine's formatting rule is by purpose (lists for facts a reader scans, prose for reasoning
  a reader follows; bold limited to a few keywords per screen, never restating the line) and cites
  the ai-slop catalog's carve-out wording; it names no model generation.
- `evals/evals.json` carries six fixture-backed cases: a long comment to BLUF with every decision
  and number preserved; a PR body with its closing line and sections intact; a short comment with
  an inline diff and no subagent; a decline routing SKILL.md prose to write-for-agents; a
  route-away of "this is a wall of text" to adhd:clarify; and a bare invocation that sets the
  standing posture.
- The doctrine file separates universal brevity rules (about half the words, no filler,
  expletives, intensifiers, or redundancy, active voice, one idea per sentence) from human-only
  scannability rules (BLUF, front-loaded headings, lists for scannable facts, bounded bold), and
  names its thresholds as a labelled fallback: split sentences over 25 words, at most 5 sentences
  per paragraph, bottom line in the first sentence.
- The reactive skill outputs BLUF first, details after, reports before and after word counts, and
  never edits a posted record in place unless explicitly told.
- For inputs longer than a few paragraphs the skill runs the fresh-context semantic-diff guard
  (the compress and ai-slop fix contract) with an added "dropped decision, number, or ask" class;
  for short comments it shows the diff inline.
- The three excluding Boundaries (ai-slop audit, write-for-humans, tighten-your-output) and
  write-for-humans eval case 5 route reader-facing prose to the new skill; write-for-agents points
  at the brevity rules.
- Presence-gated pointers exist at: work-items `track add` body, `done` closing comment, triage
  `apply-outcome`, `decompose` step 4, `attend-queue` answer-back; pull-request `create` section
  2.4.1; `bugs:write`; `planning:prd`.
- Each NN/g-derived rule carries a drift stamp and a `reference/sources.md` entry; no article text
  is vendored.
- `scripts/affected-tests.sh --run` passes for the change set.

### Captured assumptions

- Jira and ADO have no bundled write path in this marketplace, so destination guidance for them
  lives in the skill body, not on a seam verb. Revisit if a Jira or ADO adapter gains a write path.
- The consuming repo's ai-slop config governs em dashes; this plugin adds no em-dash rule. Revisit
  if the em-dash purge campaign changes `.claude/ai-slop.json`.

### Out-of-scope

- A deterministic detector script (sentence length, intensifier density, passive heuristic) and
  Vale rules: deferred post-V1 with a recorded promotion path.
- A `.claude/writing.json` config file and its setup skill: deferred; thresholds are a labelled
  fallback overridable by CLAUDE.md prose.
- A PreToolUse hook on `gh pr create` or `gh issue comment`: deferred until demonstrated demand
  and a measured budget share.
- Requesting written permission from NN/g to vendor articles.
- Exporting the doctrine as a Cursor rule file: V1 is Claude Code only. Deferred because a Cursor
  rule is a static prose copy that would drift from the doctrine; generating it is a small
  follow-up once the doctrine file exists.
- A second skill for the standing posture: the one skill carries both modes.

### Deferred questions

None. All 18 interview questions reached a decision; the register gate
(`plugins/planning/scripts/check-open-questions.sh`) exits 0 with 0 open, 0 deferred, 0 blocked.
Items the interview decided to defer are recorded under Out-of-scope with their promotion paths,
not here.

## Plan

**Goal.** Ship the `writing` plugin and its one skill, `writing:concise`, wire the four plugins
whose Boundaries currently exclude reader-facing prose to route at it, and add pointers at the
eight places this marketplace composes prose a person will read. One branch, one draft PR.

**Design.** `docs/topics/web-writing-conciseness/design/design-resolution.md` (light-design early
exit; the interview settled the public surface, and the two threads it left open are resolved
there).

### Standards grounding

This repo declares no standards index, so grounding is the repo's own ambient conventions, read
this session and cited per phase.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Plugin authoring | `AGENTS.md` "Conventions that load on demand"; `docs/PLUGIN-PHILOSOPHY.md` two-lane posture and instruction economy | team |
| Catalog taxonomy | `.claude/rules/catalog-taxonomy.md`; `docs/CATALOG-TAXONOMY.md` `presentation` row | team |
| House style | `.claude/rules/vendor-docs-are-not-style.md`; `.claude/ai-slop.json` | team |
| Attribution | `docs/conventions/upstream-drift/README.md` four-part drift stamp | team |
| Validation | `README.md` "Validate a change"; `scripts/affected-tests.sh` | team |
| PR body | `.claude/rules/pr-body-contract.md`; `.claude/source-control.md` `pr_body_required_sections` | team |

### Phase 1: Plugin skeleton and the skill body [TODO]

The integration slice. Nothing else can point at a skill that does not resolve.

| File | Action | Rationale |
|---|---|---|
| `plugins/writing/.claude-plugin/plugin.json` | CREATE | name `writing`, version `0.1.0`, MIT, keywords |
| `plugins/writing/README.md` | CREATE | what it is, the four properties, the NN/g attribution note |
| `plugins/writing/CHANGELOG.md` | CREATE | `0.1.0` initial entry |
| `plugins/writing/skills/concise/SKILL.md` | CREATE | the dual-mode skill body |
| `.claude-plugin/marketplace.json` | MODIFY | one entry, `category: presentation` |

The description's first line names all four properties (point first, no excess words, scannable
structure, factual tone) so the one-word name never carries them alone. It routes away by name
from `adhd:clarify` (restructures without shortening), `docs-hygiene:compress` (word-level, `.md`
only), `docs-hygiene:write-for-humans` (documentation genre at authoring time) and
`discipline:tighten-your-output` (in-flight terseness). Bare invocation sets the posture; an
argument targets that text. Inputs are whatever the agent can resolve with the tools it has.

No leaf-name registry entry: `concise` is carried by exactly one plugin, and the registry records
only names deliberately carried by more than one.

**Sanity Check:**

- `bash scripts/check-skill-leaf-names.sh --check` exits 0.
- `check-jsonschema --schemafile` against the plugin-manifest schema on `plugins/writing/.claude-plugin/plugin.json` exits 0.
- `python3 -c "import json;json.load(open('.claude-plugin/marketplace.json'))"` exits 0 and the `writing` entry is present with `category` equal to `presentation`.
- `/skill-quality:check concise` reports PASS.

### Phase 2: Doctrine and sources [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/writing/skills/concise/reference/doctrine.md` | CREATE | four properties, rules, thresholds |
| `plugins/writing/skills/concise/reference/sources.md` | CREATE | one drift-stamped entry per source |

Sectioned by property, not by source. Universal brevity rules are marked as such, because
`write-for-agents` points at exactly those and must not drag headings and bullets into agent-facing
text. Thresholds ship as a labelled fallback: split sentences over 25 words, at most 5 sentences
per paragraph, bottom line in the first sentence, aim at about half the draft's words. Every one is
attributed and marked overridable by the consuming repo.

The completeness floor is stated as a hard rule with its sources: no decision, number, ask, error
or warning is ever dropped, and a destination's own structural contract survives the rewrite.

**Sanity Check:**

- Every source entry carries all four drift-stamp fields: `grep -c "^upstream:" reference/sources.md` equals the entry count, and the same for the other three field names in `docs/conventions/upstream-drift/README.md`.
- No vendored article text: the longest single quoted run attributed to nngroup.com is under 25 words (`grep -n 'nngroup' reference/sources.md` then read each quote).
- `markdownlint-cli2 plugins/writing/**/*.md` reports 0 issues.
- `bash scripts/check-purged-em-dashes.sh` exits 0 for the new paths.

### Phase 3: Evals [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/writing/skills/concise/evals/evals.json` | CREATE | six cases |
| `plugins/writing/skills/concise/evals/fixtures/` | CREATE | one fixture per case that needs input |

Six cases, one per acceptance criterion that can be graded: a long tracker comment reduced to a
bottom line with every decision and number intact; a PR body whose closing keyword line and four
required sections survive; a short comment handled with an inline diff and no subagent; a decline
that routes skill-body prose to `write-for-agents`; a route-away of "this is a wall of text" to
`adhd:clarify`; and a bare invocation that sets the posture rather than editing anything.

**Sanity Check:**

- `/skill-quality:check validate-evals concise` exits 0.
- `evals.json` holds exactly 6 cases and every `files` entry resolves: `python3 -c` over the JSON asserting each path exists.

### Phase 4: Reciprocal routing [TODO]

The four skills that currently exclude this prose, plus the one that needs the brevity pointer.

| File | Action | Rationale |
|---|---|---|
| `plugins/ai-slop/skills/audit/SKILL.md` | MODIFY | Boundary routes reader-facing prose to `writing:concise` |
| `plugins/docs-hygiene/skills/write-for-humans/SKILL.md` | MODIFY | description and Boundary route existing prose and PR bodies |
| `plugins/docs-hygiene/skills/write-for-humans/evals/evals.json` | MODIFY | case 5 asserts the route, not just the decline |
| `plugins/docs-hygiene/skills/write-for-agents/SKILL.md` | MODIFY | pointer at the universal brevity rules only |
| `plugins/discipline/skills/tighten-your-output/SKILL.md` | MODIFY | the flagged markdown-terseness gap now names its owner |

Every pointer is presence-gated ("when the `writing` plugin is installed") and cites
`/writing:concise` by name, never a path into the plugin, per the encapsulation rule.

**Sanity Check:**

- `grep -rl "writing:concise" plugins/ai-slop plugins/docs-hygiene plugins/discipline` lists exactly the 5 files above.
- Each of the 5 hits is presence-gated: `grep -c "writing.*installed" <file>` is at least 1 per file.
- `/skill-quality:check` reports PASS for each modified skill.

### Phase 5: Composition-site pointers [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/work-items/skills/track/actions/add.md` | MODIFY | Build body |
| `plugins/work-items/skills/track/actions/done.md` | MODIFY | closing comment |
| `plugins/work-items/skills/triage/context/apply-outcome.md` | MODIFY | outcome comments |
| `plugins/work-items/skills/decompose/SKILL.md` | MODIFY | step 4 child bodies |
| `plugins/work-items/skills/attend-queue/SKILL.md` | MODIFY | answer-back |
| `plugins/source-control/skills/pull-request/reference/create.md` | MODIFY | section 2.4.1 body assembly |
| `plugins/bugs/skills/write/SKILL.md` | MODIFY | the report is read by a person |
| `plugins/planning/skills/prd/SKILL.md` | MODIFY | PRDs are product-owner-facing |

One line each, presence-gated, at the point where the prose is composed rather than at the top of
the file. Nothing changes shape or template; the pointer says which skill shapes the prose.

**Sanity Check:**

- `grep -rl "writing:concise" plugins/work-items plugins/source-control plugins/bugs plugins/planning` lists exactly the 8 files above.
- No template or required-section list changed: `git diff --stat` for these 8 files shows additions only, no deletions beyond reflow.
- `/skill-quality:check` reports PASS for each modified skill.

### Phase 6: Registration, versions, changelogs, validation [TODO]

| File | Action | Rationale |
|---|---|---|
| `docs/CATALOG.md` | MODIFY | new plugin row |
| `docs/SKILL-CHEAT-SHEET.md` | MODIFY | new skill row |
| `plugins/{ai-slop,docs-hygiene,discipline,work-items,source-control,bugs,planning}/.claude-plugin/plugin.json` | MODIFY | patch bump each |
| same seven `CHANGELOG.md` | MODIFY | one entry each naming the routing change |
| `docs/topics/web-writing-conciseness/PLAN.md` | MODIFY | phase tags to `[DONE]` |

Version numbers are the next patch above `origin/main` at cut time, renumbered above PR #3766 if
it merged first.

**Sanity Check:**

- `bash scripts/affected-tests.sh --run` exits 0.
- `bash scripts/check-changed-skills.sh` exits 0 with `--require-evals` in force.
- Every touched plugin has both a version bump and a changelog entry: for each, `git diff origin/main -- <plugin>/.claude-plugin/plugin.json <plugin>/CHANGELOG.md` is non-empty on both paths.
- `bash scripts/check-purged-em-dashes.sh` exits 0.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Extend `docs-hygiene` instead of a new plugin | Its skills are `.md`-only, require `markdownlint-cli2`, and share a clean-tree fallback; the Jira and PR cases need none of that | If the plugin stays one skill for two releases and nothing else joins it, fold it into docs-hygiene |
| Extend `ai-slop`'s rewrite guide | ai-slop detects tells, not length or structure, and its catalog is a closed CC BY-SA corpus | If the doctrine collapses to a word list with no reader model |
| Two PRs (plugin, then pointers) | User chose one branch and one PR | If review latency on the combined diff blocks the plugin from landing |
| Ship a detector script in V1 | Every rule needs a crosswalk row and a co-located test; word-count delta is the best-evidenced measure and needs no script | If judgment-only V1 produces inconsistent rewrites across sessions |
| A PreToolUse hook on `gh pr create` | The hook budget is over ceiling and rule 2 never relaxes | If the budget is re-measured with headroom and demand is demonstrated |

### Test strategy

There is no runtime here: every artifact is markdown read by a model. Verification is therefore
the repo's own static gates plus per-skill evals, which is the pattern every prose skill in this
marketplace already uses.

- **Test boundaries.** The skill's public surface is its frontmatter description and its argument
  contract (bare equals posture, argument equals target). Both already exist as a convention; this
  change introduces no new interface for testability.
- **Evals are the behavioral tests**, written before the skill body is finalized (the six cases in
  Phase 3 are derived from the Brief's acceptance criteria, so they are red until the body
  satisfies them). `/skill-quality:check validate-evals` is the runner.
- **Static gates** are the regression net: `skill-quality:check`, `check-skill-leaf-names.sh`,
  `check-changed-skills.sh --require-evals`, markdownlint, the em-dash ratchet, and
  `affected-tests.sh --run`.
- **The routing change is the one behavioral regression risk.** Phases 4 and 5 narrow three
  Boundaries; `write-for-humans` eval case 5 is updated in the same phase that narrows it, so the
  assertion moves with the behavior rather than lagging it.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Merge conflict with PR #3766 in `marketplace.json`, `CATALOG.md`, `SKILL-CHEAT-SHEET.md` | High | Low | Rebase after it merges; these are append-only list files |
| The doctrine reads as a second `write-for-humans` and nobody routes correctly | Medium | High | Descriptions state the split explicitly; eval cases 4 and 5 assert the routes |
| A pointer edit changes a required-section template by accident | Low | High | Phase 5 sanity check asserts additions only |
| NN/g attribution drifts or over-quotes | Low | Medium | Phase 2 sanity check bounds quote length and asserts drift stamps |
| Eight plugin version bumps collide with another session's bumps | Medium | Low | Bump at cut time in Phase 6, not incrementally |

## Blast radius

**Blast radius: MEDIUM.** Eight plugins touched and three Boundaries narrowed, so the routing
surface of several installed skills changes. Nothing executes: no hooks, no scripts, no runtime,
no schema. Every change is reversible by reverting one PR, and the static gates catch structural
breakage before merge.

**Stress-test needed:** No formal `/planning:devils-advocate` pass. The plan-reviewer sub-agent
plus the locked, verified upstream artifacts cover it; no trigger in the stress-test criteria
matches a docs-only change with no runtime and no data migration.

## Stress-test summary

Step 3 plan-reviewer sub-agent: dispatched, findings applied (recorded below at approval time).
Step 4 formal stress-test: skipped, blast radius MEDIUM with no matching trigger.

## Execution shape

**Fully sequential. Phase 1 gates every other phase**, because phases 2 through 5 all cite a skill
that must exist first, and Phase 6 bumps versions for whatever phases 1 through 5 actually touched.

Phases 4 and 5 are file-disjoint from each other and could run in parallel, but the independent
work is roughly 100 lines of one-line pointer edits across 13 files, and both feed Phase 6's
version bumps. The coordination cost exceeds the saving, so parallelism is documented and not
recommended.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | The skill body is the judgment-heavy artifact of the whole change |
| 2 | main session | Doctrine wording is the deliverable; house style is judgment |
| 3 | main session | Eval cases encode the acceptance criteria |
| 4 | main session | Boundary wording decides routing; a wrong word makes two skills unroutable |
| 5 | main session | Mechanical, but each pointer must match its host file's voice |
| 6 | main session | Version arithmetic depends on `origin/main` at cut time |

## Open questions

None blocking. One timing dependency: PR #3766 edits three of the same list files, so rebase after
it merges.

## Handoff to implementation

### User-approval gates

- Before opening the PR, since one draft PR carrying eight plugin version bumps is the agreed
  shape and the body must satisfy `pr-issue-linkage` (a closing keyword line plus Summary, Fix,
  Verification, Related).
- Before any scope expansion beyond the six phases, in particular before adding a detector script,
  a config file, a hook, or a Cursor export, all of which the Brief places out of scope.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, six phases, all main-session, commit per phase. Phase 1 is the integration slice. No
scope-fencing tables are needed because no parallel agents run. The sequential path is the only
path, so there is no fallback to document.

### Mechanical work

- One commit per phase, subject shaped per the resolved Conventional Commits convention, with the
  attribution trailers.
- Push after each phase so the branch never holds unpushed work.
- Open the PR as a draft and flip it to ready when Phase 6 is green, per `AGENTS.md`.
- Validate with `scripts/affected-tests.sh --run`, never the full suite.
