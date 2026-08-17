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
- Mechanical rules are context-exemptible, never blindly absolute: code blocks, fixtures, and deliberate stylistic conventions must be exemptible via configuration. *(Scope note 2026-08-17, approval round: the em-dash rule is zero-tolerance by default — ANY em-dash in prose flags; documents that require them opt out via config or in-file marker. Other rules stay threshold-based. Supersedes the earlier "never absolute bans" phrasing for this one rule.)*
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

- **Q12 (rule roster + thresholds)**: candidate mechanical roster pinned in Phase 3 below (12 rules); final thresholds and survivorship calibrated against fixtures and a repo-corpus false-positive pass during implementation — a rule that cannot clear calibration ships in the catalog as `recorded-only`, never as an uncalibrated detector. **Exception fixed at approval (user decision): `rule-em-dash` is zero-tolerance by default — any em-dash in prose outside code fences flags; exemption is per-document (config path-lists or in-file marker), not per-threshold.**
- **Q13 (skill name)**: **`audit`** (`/ai-slop:audit`) — `docs/PLUGIN-PHILOSOPHY.md` verb table: `audit` = read-only findings report, "mutation only behind an explicit user override such as an autofix argument" — which is exactly the Brief's detect-then-fix contract. The fix path is the `fix` argument of the same skill.
- **Q14 (prioritization mechanics)**: repo-wide runs order work by impact class first (instruction surfaces: `CLAUDE.md`, `AGENTS.md`, `.claude/rules/**`, `**/SKILL.md`, `README.md`), then by change frequency (`git log --since=90.days --name-only` count over tracked `.md`). Ordering affects report order and chunk order only, never inclusion.

**Standards grounding**: plan built against `docs/conventions/detector-findings/README.md` (producer fields, rule-id form `ai-slop/audit/rule-<slug>`, crosswalk admission test, coexistence, `## Surfaces` decline counts), `plugins/review/skills/fanout/context/default-mode.md` "Findings-file shape" + cell-escaping, `plugins/review/context/severity.md` tier tests, `docs/conventions/upstream-drift/README.md` four-part record, `docs/conventions/shell-test-helpers/README.md`, `docs/PLUGIN-PHILOSOPHY.md` naming/setup/component stances, and the sibling detector shape (`plugins/docs-hygiene/skills/audit-noise/scripts/detect.sh`).

### Phase 1: Catalog distillation [DONE]

Create `plugins/ai-slop/skills/audit/reference/catalog.md`: every tell from Wikipedia "Signs of AI writing" (fetched this session; sections: Content, Language and grammar, Style, Communication intended for the user, Markup, Citations, Edit summaries, Miscellaneous, plus Historical), one entry per tell. **Entry marker pinned**: each entry is an H3 of the form `### rule-<slug> — <tell name>`, so entries are countable by `grep -c '^### rule-'`. Entry fields: `id / name / description (our words) / detectability (mechanical|judgment) / applicability (general-prose|wikipedia-specific) / v1 (script|rubric|recorded-only)`. First work item: re-fetch the page, record its revision id and count its tells — that count (not a plan-time guess) becomes the sanity floor. **Full CC BY-SA 4.0 attribution block** scoped to catalog.md: source page link, revision id, changes-made statement (distilled/reworded derivative), license notice with link, and an explicit statement that catalog.md's adapted material is licensed CC BY-SA 4.0 (ShareAlike). Four-part upstream-drift record (claim, basis = page URL + `oldid`, as-of date, recheck trigger = a recurring observable occasion — each ai-slop release and each fleet audit — chosen over per-revision because the page takes 50+ edits/week (measured 2026-08-17), which would fire continuously). Wikipedia-specific tells (wikitext markup, citation templates, edit summaries, AfC) are `recorded-only`.

**Sanity Check:** `grep -c '^### rule-' catalog.md` equals the tell count recorded by this phase's first work item; `grep -q 'CC BY-SA 4.0' catalog.md`; `grep -qE 'oldid=[0-9]+' catalog.md`; `grep -qi 'changes were made\|changes-made' catalog.md`.

### Phase 2: Tracer bullet — scaffold + two-rule detector, end to end [DONE]

*(Execution note 2026-08-17: fixtures are built inline in detect.test.sh's tmpdir per the audit-noise precedent, instead of shipped `scripts/fixtures/` files — removes the self-detection exemption surface for fixtures entirely.)*

Plugin scaffold (`.claude-plugin/plugin.json` on the `naming` plugin's manifest shape, `README.md`, `CHANGELOG.md`, `skills/audit/` skeleton `SKILL.md`, **plus a `skills/setup/` skill** — required by `docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" because the plugin has a consumer-project configuration surface). `scripts/detect.sh` implements two seed rules (`rule-em-dash`, `rule-ai-vocabulary`) with: word-boundary matching; fenced-code-block and inline-code exemption; **an in-file opt-out marker** (HTML comment, audit-noise's `is_ignore_line_marker` precedent) honored line- and block-level; **consumer config read** (thresholds, banned-word additions/removals, path exclusions) resolved per `docs/conventions/config-cascade/README.md`, with **neutral defaults not calibrated to this repo**; **portable Unicode matching** — `LC_ALL=C` byte-sequence classes for em-dash (`\xE2\x80\x94`), curly quotes, and emoji ranges, POSIX ERE only (no `grep -P`), per the cross-platform contract; and the sibling chunk affordances (`--paths-file`, `--offset`, `--limit`) with repo-wide input from `git ls-files '*.md'`. `scripts/fixtures/` (slop + clean samples), `scripts/detect.test.sh` per shell-test-helpers. **detect.sh emits its own parseable report only** — the findings FILE is model-persisted by the skill (Phase 5), not by the script.

**Sanity Check:** `bash detect.test.sh` exit 0; slop fixture fires both rule ids with the fired condition in output (`rule-ai-vocabulary`: the threshold that fired; `rule-em-dash`: the zero-tolerance marker), clean fixture fires zero; a fixture line carrying the opt-out marker is not flagged (test assertion); `shellcheck` + `shfmt -d` clean; `LC_ALL=C bash detect.sh <slop-fixture>` produces identical output to the default locale (portability probe).

### Phase 3: Full mechanical roster + calibration [DONE]

Extend `detect.sh` to the candidate roster: `rule-em-dash`, `rule-emoji-formatting`, `rule-ai-vocabulary`, `rule-significance-inflation` (renamed from the roster draft's `rule-significance-phrases` to the catalog's committed id; "pivotal moment", "marks a shift", "stands as a testament", "rich tapestry"…), `rule-negative-parallelism` ("not just X but Y" / "not X, but Y" / "isn't X; it's Y"), `rule-rule-of-three`, `rule-copulative-avoidance` ("serves as", "marks a", "represents a"…), `rule-challenges-conclusion` ("Despite its …, faces challenges…"), `rule-curly-artifacts` (curly quotes/apostrophes + LLM Unicode residue), `rule-llm-citation-artifacts` (`oaicite`, `[cite:`, `grok_card`, `attached_file`), `rule-knowledge-cutoff-disclaimer`, `rule-utm-params`. Per-rule fixtures (positive + negative). Calibration pass: run repo-wide over tracked `.md` **via consumer config carrying this repo's exemptions** (its em-dash house style is config, never baked into shipped defaults); demote incurable rules to `recorded-only` in the catalog. **Self-corpus exemption**: default path exclusions ship for the plugin's own `reference/catalog.md` and `scripts/fixtures/**`; the crosswalk table in the convention doc and this plan get in-file opt-out markers when dogfooding. Structural-markdown tells (heading hierarchy, multiple H1, title case) are EXCLUDED — owned by the markdown-format plugin's linter.

**Sanity Check:** `detect.test.sh` exit 0 with ≥1 positive and ≥1 negative fixture assertion per shipped rule; `shellcheck` and `shfmt -d` clean; calibration outcome recorded per rule in catalog.md (`v1` column final); a config-file fixture test proves a threshold override and a path exclusion take effect.

### Phase 4: Severity-crosswalk rows [DONE]

First work item: baseline `bash scripts/check-detector-findings-crosswalk.sh --check` run (must be exit 0 BEFORE our rows land — a dirty baseline is not ours to inherit silently). Then append one argued row per shipped rule to the crosswalk table in `docs/conventions/detector-findings/README.md`: **tier argued per row from `severity.md` tests, first match winning — flat across rows unless a row's own test argues otherwise** (the artifact-class rules — `rule-llm-citation-artifacts`, `rule-knowledge-cutoff-disclaimer` — may legitimately argue IMPORTANT's degradation limb; the argument is the row, not this plan). Auto-applicable No except where a row argues contained meaning-preserving remediation (`rule-utm-params` is the candidate). Selection is mechanical (no withholding verdicts), fail-safe by construction; each row states its decline evidence (code-fence/marker/config exemptions, counted per rule in `## Surfaces`).

**Sanity Check:** `bash scripts/check-detector-findings-crosswalk.sh --check` exit 0 after the rows; `grep -c '| ai-slop/audit/rule-' docs/conventions/detector-findings/README.md` equals the shipped-rule count.

### Phase 5: SKILL.md — audit flow, judgment rubric, findings persist, fix action [TODO]

Author the full skill: frontmatter (description with triggers, `argument-hint: [audit|fix] [target]`, allowed-tools for `detect.sh`), default read-only audit (empty target → repo-wide over tracked `.md` minus configured exclusions, ordered per Q14; path target → scoped), chunked `detect.sh` invocation via `--paths-file`/`--offset`/`--limit`. **Findings-file persistence is model-executed prose following `plugins/mutation-testing/skills/audit/context/persist-findings.md`'s pattern**: runtime-fetch the detector-findings contract from its raw URL, refuse to persist when unreachable, resolve the findings home through the full rung order with the self-ignore guard, and emit the complete producer field set — `type: review-findings`, `date:` (colon-free UTC), `branch:`, rule id + fired threshold leading every `Finding` cell, escaped cells, non-overwrite naming, `## Surfaces` with declined-candidate counts per rule id — **mapping tiers to the consuming project's severity vocabulary at emit time** (severity.md consumer precedence). Judgment-rubric layer covers the catalog's `rubric` tells; judgment findings go to the human report only, never the findings file (V1 relay boundary). `fix` action: explicit-invocation-only, applies script findings + judgment rewrites per file with a mandatory fresh-context semantic-diff subagent that reverts SEMANTIC LOSS or AMBIGUITY (compress's model), per-file close-out loop (apply → verify → close); **after fix completes, re-run detect and re-emit current findings so no stale findings file survives its own remediation** (re-run-never-replay, applied to our own fix path).

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/ai-slop/skills" bash plugins/skill-quality/scripts/check-skill.sh audit` exit 0 (and `… check-skill.sh setup` exit 0); `grep -q 'semantic' SKILL.md`; `grep -q 'refuse' SKILL.md` (unreachable-contract refusal present); an end-to-end manual run over the fixture corpus produces a findings file passing a frontmatter + leading-rule-id grep assertion (recorded in the phase close-out, not in detect.test.sh).

### Phase 6: Registration + docs + quality gates [TODO]

Marketplace entry in `.claude-plugin/marketplace.json` (category, tags), `docs/CATALOG.md` row, plugin README (purpose, actions, catalog pointer, config surface, dogfood follow-up noted), plugin CHANGELOG 0.1.0. **Convention adopter bookkeeping**: add the ai-slop row to `docs/conventions/detector-findings/README.md` "Adopters" (tabled only now — after conformance exists) with the minor version bump in that convention's `CHANGELOG.md`; add the catalog's upstream-drift adopter row per that convention's adopted-on-touch mechanism (+ its changelog bump). Repo-wide lint gates (markdownlint-cli2, typos, editorconfig-checker).

**Sanity Check:** marketplace.json passes the repo's existing validation path (`check-jsonschema` against the marketplace schema, or the CI script that owns it — resolve which during the phase, cite it in the close-out); `grep -q 'ai-slop' docs/CATALOG.md`; `grep -q 'ai-slop' docs/conventions/detector-findings/README.md` (Adopters row); markdownlint + typos exit 0 on changed files.

## Test strategy

Deterministic layer is TDD-shaped: fixtures are written with expected findings BEFORE rules are implemented (Red), `detect.test.sh` asserts per-rule positive/negative outcomes (Green), calibration refactors thresholds (Refactor). Skill-layer behavior (audit flow, fix guard) is verified by `skill-quality:check` plus a manual end-to-end run on the fixture corpus; findings-file conformance is asserted by the test script (frontmatter + table shape + cell escaping). No mocks anywhere — real files, real git.

## Alternatives considered

- **Judgment findings into the relay too** (mutation-testing precedent) — rejected for V1: each judgment rule would need its own argued crosswalk row and evidence class; cost disproportionate before the rubric has field history. Revisit post-V1.
- **Extending docs-hygiene instead of a new plugin** — rejected in the Brief (Q5).
- **Hook-first enforcement** — rejected in the Brief (Q9, out-of-scope).

## Risks and mitigations

- **False positives on deliberate house style** (this repo uses em-dashes heavily) → exemption calibration in Phase 3 against the live corpus before any crosswalk row lands: `rule-em-dash` calibrates per-document exemptions ONLY (the Q12 zero-tolerance exception — never re-thresholded), other rules calibrate thresholds; the `recorded-only` demotion path EXCLUDES `rule-em-dash` (user-fixed — demoting it requires a user gate, not calibration judgment).
- **Substring traps** (`slop`→`slope` class) → word-boundary matching mandated in Phase 2 seed rules and tested per rule.
- **Crosswalk admission friction** → rows drafted from severity.md tests read this session; if a row cannot be argued, the rule demotes to `recorded-only` rather than shipping unargued.
- **Wiki page drift** → four-part upstream record with revision-pinned basis and named recheck trigger.
- **Cross-platform Unicode matching** (BSD grep, Git Bash locales) → `LC_ALL=C` byte-sequence classes + POSIX ERE only; portability probe in Phase 2's sanity check; any unverifiable platform recorded as an honest gap, not assumed.
- **Dual remediation routes going stale** (our `fix` vs `review:fanout fix` over one findings file) → post-fix re-detect + re-emit in Phase 5.

## Blast radius

LOW — purely additive: a new plugin directory, append-only rows in one shared registry table (CI-checked by `check-detector-findings-crosswalk.sh`), and registration entries. No existing plugin, hook, or consumer behavior changes. Stress-test: plan-reviewer sub-agent (mandatory) only; `/planning:devils-advocate` not triggered.

## Stress-test summary

Fresh-context plan reviewer (Step 3) returned 1 CRITICAL / 8 IMPORTANT / 3 SUGGESTION; all 12 verified against the actual convention files and applied: (1) the Brief's exemptible-via-configuration constraint now has a config surface (config-cascade), a required `setup` skill, an in-file opt-out marker, and neutral shipped defaults; (2) Phase 5's check-skill invocation corrected to the name-based `CHECK_SKILL_SKILLS_ROOT` form; (3) findings emission extended to the full producer field set (`date:`, leading rule id + threshold, non-overwrite naming, `## Surfaces` decline counts); (4) emitter locus fixed — model-executed persist on the mutation-testing fetch-and-refuse pattern, out of detect.test.sh; (5) portable Unicode matching stated (`LC_ALL=C` byte classes, POSIX ERE); (6) self-corpus exemptions added; (7) crosswalk baseline run, Adopters rows, and convention changelog bumps added; (8) fix action re-emits findings post-apply (no stale relay file); (9) full CC BY-SA 4.0 attribution block; (10) per-row tier arguments unlocked from the plan's flat pre-commitment + emit-time severity mapping; (11) Phase 1 sanity pinned to a real entry marker and in-phase count floor; (12) chunk affordances and repo-wide list source specified.

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
- [EXEC-SHAPE] Seed-rule pair for the tracer bullet (`rule-em-dash`, `rule-ai-vocabulary`).
- [EXEC-SHAPE] Config surface resolves per the config-cascade convention; findings persist follows the mutation-testing fetch-and-refuse pattern (both are the repo's established mechanism for their job, not new design).

### Mechanical work

Commit per phase (conventional commits, `feat(ai-slop):` for 2–6, `docs(ai-slop):` for 1), push after each commit; each phase's sanity check runs before its commit; sequential fallback N/A (already sequential). PLAN.md phase tags advance with each phase's commit.
