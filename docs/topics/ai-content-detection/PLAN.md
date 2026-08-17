# ai-content-detection — PLAN

## Brief

### TLDR

- New marketplace plugin **`ai-slop`**: detect and remove AI-writing tells ("slop") from checked-in markdown prose.
- One skill: read-only **audit** as the default action, **fix** as an explicit follow-up action (chainable in one invocation on request).
- Two-layer detection: deterministic `detect.sh` for mechanical tells (em-dashes, emojis, banned vocabulary, "not X but Y" constructions, Unicode artifacts) + a judgment rubric for non-mechanical signs (puffery, editorializing, rule-of-three, sycophantic framing).
- Rule set seeded from Wikipedia's ["Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), distilled into a bundled versioned catalog under upstream-drift tracking, plus our own additions layered explicitly on top.
- Findings conform to the detector-findings convention so `review:fanout fix` can consume them; the fix action is guarded by a semantic-diff subagent.

### Goal

Give the fleet a first-class capability to detect and clean AI-writing tells in written output — the text artifacts themselves. An audit pass surfaces every sign from the Wikipedia catalog plus mechanical tells across a repo's checked-in, agent-consumed markdown prose; an opt-in fix pass rewrites the findings without semantic loss. Default scope is the entire repo, prioritizing high-velocity files (frequently changed) and high-impact instruction surfaces (`CLAUDE.md`, `AGENTS.md`, and similar), unless the user names a narrower target.

### Constraints

- Findings files must conform to the shape owned by `plugins/review/skills/fanout/context/default-mode.md` and the producer rules in `docs/conventions/detector-findings/README.md` — including one argued severity-crosswalk row per deterministic rule (enforced by `scripts/check-detector-findings-crosswalk.sh`).
- The fix action never runs without an explicit user request, and every applied rewrite passes a semantic-diff subagent that reverts any change introducing semantic loss or ambiguity (the `docs-hygiene:compress` model).
- Wikipedia content is CC BY-SA — the bundled catalog must attribute the source page and revision, per the upstream-drift convention's citation shape.
- Mechanical rules are threshold- and context-based, never absolute bans: code blocks, fixtures, and deliberate stylistic conventions (this repo's own docs use em-dashes intentionally) must be exemptible via configuration.
- Marketplace conventions apply: plugin registered in `.claude-plugin/marketplace.json`, standard plugin layout (README, CHANGELOG, skills/), skill passes `skill-quality:check`.

### Acceptance criteria

- `plugins/ai-slop/` exists, registered in `.claude-plugin/marketplace.json` with category and tags.
- The skill's default action is read-only and reports findings; `fix` applies rewrites only on explicit request; "detect and rewrite" in one invocation chains both.
- A bundled reference catalog covers every tell on the Wikipedia "Signs of AI writing" page, each classified **mechanical** or **judgment**, with source URL + revision recorded per the upstream-drift convention (recheck trigger included).
- `detect.sh` deterministically detects the mechanical subset (~8–15 rules at V1); each rule has an argued severity-crosswalk row and the crosswalk check script passes.
- Detector output includes test fixtures (sample slop text with known expected findings) and a passing test script per the shell-test-helpers convention.
- Findings emitted by the audit are consumable by `review:fanout fix` (frontmatter `type: review-findings`, correct `branch:`).
- Empty-target invocation runs repo-wide over tracked markdown with high-velocity/high-impact prioritization; a path argument narrows scope to that target.
- Execution contract for repo-wide runs: per-file loop — detect, report; on fix: apply, semantic-diff verify, close. A file is closed when its findings are fixed, explicitly suppressed, or reverted-with-reason.

### Captured assumptions

- The Wikipedia page remains the single upstream source for V1 — revisit if it is restructured, deleted, or a materially better catalog emerges (upstream-drift recheck trigger).
- ~8–15 mechanical rules is the right V1 detector size — revisit if crosswalk authoring proves cheaper/costlier than expected during implementation.
- One skill (audit default + fix action) is sufficient surface — revisit if fix grows enough distinct behavior to warrant its own skill.

### Out-of-scope

- **Write-hooks** (flagging tells on every markdown write, format-plugin style) — post-V1, once the rule set has stabilized against real usage.
- **Non-repo / arbitrary text** (emails, posts, pasted drafts) — named future expansion.
- **Code comments** — owned by `code-tidying:audit-comment-residue`; boundary stays there.
- **Commit messages and PR bodies** — named future expansion.
- **Other content categories with their own actions/criteria/rubrics** — the user's expansion vision, post-V1.
- **Dogfood sweep of this repo's own skills and instructions** (removing em-dashes and other tells from our corpus) — explicit follow-up task after V1 ships; the plugin's first real-world target.

### Deferred questions

- Q12 — Exact V1 mechanical-rule roster and each rule's thresholds/exemptions — defer until planning; **arbiter: /planning:plan**
- Q13 — Primary skill name (`check` vs `audit`) and action-verb surface — defer until planning; **arbiter: /planning:plan**
- Q14 — High-velocity/high-impact prioritization mechanics (git-log frequency window, instruction-surface list) — defer until planning; **arbiter: /planning:plan**

## Plan

**Deferred-question resolutions** (arbiter `/planning:plan`, per the Brief):

- **Q12 (rule roster + thresholds)**: candidate mechanical roster pinned in Phase 3 below (12 rules); final thresholds and survivorship calibrated against fixtures and a repo-corpus false-positive pass during implementation — a rule that cannot clear calibration ships in the catalog as `recorded-only`, never as an uncalibrated detector.
- **Q13 (skill name)**: **`audit`** (`/ai-slop:audit`) — `docs/PLUGIN-PHILOSOPHY.md` verb table: `audit` = read-only findings report, "mutation only behind an explicit user override such as an autofix argument" — which is exactly the Brief's detect-then-fix contract. The fix path is the `fix` argument of the same skill.
- **Q14 (prioritization mechanics)**: repo-wide runs order work by impact class first (instruction surfaces: `CLAUDE.md`, `AGENTS.md`, `.claude/rules/**`, `**/SKILL.md`, `README.md`), then by change frequency (`git log --since=90.days --name-only` count over tracked `.md`). Ordering affects report order and chunk order only, never inclusion.

**Standards grounding**: plan built against `docs/conventions/detector-findings/README.md` (producer fields, rule-id form `ai-slop/audit/rule-<slug>`, crosswalk admission test, coexistence, `## Surfaces` decline counts), `plugins/review/skills/fanout/context/default-mode.md` "Findings-file shape" + cell-escaping, `plugins/review/context/severity.md` tier tests, `docs/conventions/upstream-drift/README.md` four-part record, `docs/conventions/shell-test-helpers/README.md`, `docs/PLUGIN-PHILOSOPHY.md` naming/setup/component stances, and the sibling detector shape (`plugins/docs-hygiene/skills/audit-noise/scripts/detect.sh`).

### Phase 1: Catalog distillation [TODO]

Create `plugins/ai-slop/skills/audit/reference/catalog.md`: every tell from Wikipedia "Signs of AI writing" (fetched this session; sections: Content, Language and grammar, Style, Communication intended for the user, Markup, Citations, Edit summaries, Miscellaneous, plus Historical), one entry per tell with `id / name / description (our words) / detectability (mechanical|judgment) / applicability (general-prose|wikipedia-specific) / v1 (script|rubric|recorded-only)`. Page-level CC BY-SA attribution and a four-part upstream-drift record (claim, basis = page URL + revision id, as-of date, recheck trigger = new revision touching a mapped section). Wikipedia-specific tells (wikitext markup, citation templates, edit summaries, AfC) are `recorded-only`.

**Sanity Check:** `grep -c '^| ai-slop/audit/rule-\|^### ' catalog.md` count ≥ 40 entries; `grep -q 'CC BY-SA' catalog.md`; `grep -qE 'oldid=[0-9]+' catalog.md` (revision-pinned basis).

### Phase 2: Tracer bullet — scaffold + two-rule detector, end to end [TODO]

Plugin scaffold (`.claude-plugin/plugin.json` on the `naming` plugin's manifest shape, `README.md`, `CHANGELOG.md`, `skills/audit/` skeleton `SKILL.md`) plus `scripts/detect.sh` implementing two seed rules (`rule-em-dash-density`, `rule-ai-vocabulary`) with word-boundary matching and fenced-code-block exemption, `scripts/fixtures/` (one slop sample, one clean sample), `scripts/detect.test.sh` per shell-test-helpers, and findings-file emission (frontmatter `type: review-findings` + `branch:` + `## Findings` table with escaped cells, written via the topic-docs non-interactive resolution).

**Sanity Check:** `bash detect.test.sh` exit 0; running `detect.sh` on the slop fixture emits both rule ids and on the clean fixture emits zero findings; the emitted findings file's frontmatter contains `type: review-findings` and the current branch (grep assertions in the test).

### Phase 3: Full mechanical roster + calibration [TODO]

Extend `detect.sh` to the candidate roster: `rule-em-dash-density`, `rule-emoji-formatting`, `rule-ai-vocabulary`, `rule-significance-phrases` ("pivotal moment", "marks a shift", "stands as a testament", "rich tapestry"…), `rule-negative-parallelism` ("not just X but Y" / "not X, but Y" / "isn't X; it's Y"), `rule-rule-of-three`, `rule-copulative-avoidance` ("serves as", "marks a", "represents a"…), `rule-challenges-conclusion` ("Despite its …, faces challenges…"), `rule-curly-artifacts` (curly quotes/apostrophes + LLM Unicode residue), `rule-llm-citation-artifacts` (`oaicite`, `[cite:`, `grok_card`, `attached_file`), `rule-knowledge-cutoff-disclaimer`, `rule-utm-params`. Per-rule fixtures (positive + negative). Calibration pass: run repo-wide over tracked `.md`, tune thresholds/word-boundaries until false positives on deliberate house style are controlled; demote incurable rules to `recorded-only` in the catalog. Structural-markdown tells (heading hierarchy, multiple H1, title case) are EXCLUDED — owned by the markdown-format plugin's linter.

**Sanity Check:** `detect.test.sh` exit 0 with ≥1 positive and ≥1 negative fixture assertion per shipped rule; `shellcheck` and `shfmt -d` clean on both scripts; calibration outcome recorded per rule in catalog.md (`v1` column final).

### Phase 4: Severity-crosswalk rows [TODO]

Append one argued row per shipped rule to the crosswalk table in `docs/conventions/detector-findings/README.md`: tier argued from `severity.md` tests (expected landing: SUGGESTION — CRITICAL/IMPORTANT limbs fail: a prose tell makes nothing produce a wrong result and names no degradation trigger; flat across the producer's emitting rules), auto-applicable No for all rows except `rule-utm-params` (contained, meaning-preserving strip) — final call argued in each row. Selection is mechanical (no withholding verdicts), so the fail-safe criterion is met by construction; the decline evidence form (code-block/fixture exemptions) is stated in the rows.

**Sanity Check:** `bash scripts/check-detector-findings-crosswalk.sh --check` exit 0; `grep -c '^| ai-slop/audit/rule-' docs/conventions/detector-findings/README.md` equals the shipped-rule count.

### Phase 5: SKILL.md — audit flow, judgment rubric, fix action [TODO]

Author the full skill: frontmatter (description with triggers, `argument-hint: [audit|fix] [target]`, allowed-tools for `detect.sh`), default read-only audit (empty target → repo-wide over tracked `.md` minus `**/fixtures/**` and `CHANGELOG.md`, ordered per Q14; path target → scoped), chunked `detect.sh` invocation, judgment-rubric layer covering the catalog's `rubric` tells (significance inflation, superficial analysis, promotional tone, vague attribution, collaborative communication, elegant variation) — judgment findings go to the human report only, never the findings file (V1 relay boundary); `fix` action: explicit-invocation-only, applies script findings + judgment rewrites per file with a mandatory fresh-context semantic-diff subagent that reverts SEMANTIC LOSS or AMBIGUITY (compress's model), per-file close-out loop (apply → verify → close) per the Brief's execution contract.

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh plugins/ai-slop/skills/audit/SKILL.md` (or the plugin's documented check entrypoint) exit 0; `grep -q 'semantic' SKILL.md` fix-guard present; `grep -q 'disable-model-invocation\|user-invocable' SKILL.md` frontmatter complete.

### Phase 6: Registration + docs + quality gates [TODO]

Marketplace entry in `.claude-plugin/marketplace.json` (category, tags), `docs/CATALOG.md` row, plugin README (purpose, actions, catalog pointer, dogfood follow-up noted), CHANGELOG 0.1.0, repo-wide lint gates (markdownlint-cli2, typos, editorconfig-checker, actionlint N/A).

**Sanity Check:** `check-jsonschema` (or the repo's marketplace validation path) passes on marketplace.json; `grep -q 'ai-slop' docs/CATALOG.md`; markdownlint + typos exit 0 on changed files.

## Test strategy

Deterministic layer is TDD-shaped: fixtures are written with expected findings BEFORE rules are implemented (Red), `detect.test.sh` asserts per-rule positive/negative outcomes (Green), calibration refactors thresholds (Refactor). Skill-layer behavior (audit flow, fix guard) is verified by `skill-quality:check` plus a manual end-to-end run on the fixture corpus; findings-file conformance is asserted by the test script (frontmatter + table shape + cell escaping). No mocks anywhere — real files, real git.

## Alternatives considered

- **Judgment findings into the relay too** (mutation-testing precedent) — rejected for V1: each judgment rule would need its own argued crosswalk row and evidence class; cost disproportionate before the rubric has field history. Revisit post-V1.
- **Extending docs-hygiene instead of a new plugin** — rejected in the Brief (Q5).
- **Hook-first enforcement** — rejected in the Brief (Q9, out-of-scope).

## Risks and mitigations

- **False positives on deliberate house style** (this repo uses em-dashes heavily) → threshold + exemption calibration phase (Phase 3) against the live corpus before any crosswalk row lands; `recorded-only` demotion path.
- **Substring traps** (`slop`→`slope` class) → word-boundary matching mandated in Phase 2 seed rules and tested per rule.
- **Crosswalk admission friction** → rows drafted from severity.md tests read this session; if a row cannot be argued, the rule demotes to `recorded-only` rather than shipping unargued.
- **Wiki page drift** → four-part upstream record with revision-pinned basis and named recheck trigger.

## Blast radius

LOW — purely additive: a new plugin directory, append-only rows in one shared registry table (CI-checked by `check-detector-findings-crosswalk.sh`), and registration entries. No existing plugin, hook, or consumer behavior changes. Stress-test: plan-reviewer sub-agent (mandatory) only; `/planning:devils-advocate` not triggered.

## Stress-test summary

<!-- filled after the plan-reviewer sub-agent pass -->

## Execution shape

Fully sequential in the main session — Phase 1's catalog feeds Phase 3's roster and Phase 5's rubric; Phase 2 gates 3, 3 gates 4, 4–5 gate 6. Phases 1 and 2 are file-disjoint and could pair as a wave, but the saving is immaterial against subagent overhead for a tightly-coupled single-plugin build. Per-phase routing: all phases main-session; the semantic-diff guard inside the `fix` action (Phase 5's design) and the Step 3 plan review are the only subagent surfaces.

## Open questions

None at approval time — Q12–Q14 resolved above; anything discovered mid-build routes back per the mid-flight-pivot rule.

## Handoff to implementation

### User-approval gates

- Phase 4's final auto-applicability call on `rule-utm-params` if implementation finds any meaning-bearing counter-example [FALLBACK — confirm or override at that point].
- Any roster demotion to `recorded-only` that drops shipped-rule count below 8 (Brief's ~8–15 assumption) — surface before proceeding.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential main-session execution, phases 1→6 as ordered above.
- [EXEC-SHAPE] Judgment findings stay out of the findings file in V1 (human report only).
- [EXEC-SHAPE] Q14 prioritization mechanics as resolved above.
- [EXEC-SHAPE] Seed-rule pair for the tracer bullet (`rule-em-dash-density`, `rule-ai-vocabulary`).

### Mechanical work

Commit per phase (conventional commits, `feat(ai-slop):` for 2–6, `docs(ai-slop):` for 1), push after each commit; each phase's sanity check runs before its commit; sequential fallback N/A (already sequential). PLAN.md phase tags advance with each phase's commit.
