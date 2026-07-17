# interview-batch-rounds

## Brief

> **Scope-change note (2026-07-17, during /architect):** the surface-preference userConfig key changed
> from `question_surface` (string enum `prose|ask-user-question`, default `prose`) to
> `use_ask_user_question` (boolean, default `false`). Forced by the verified plugins-reference schema —
> userConfig has no enum type, and a free-string key nobody validates is worse than a boolean. The
> substance (prose default, AskUserQuestion opt-in) is unchanged. Made under the Brief's own deferred
> question 1, whose arbiter is /architect ("exact value set and any additional interview userConfig
> keys"). Bullets below updated in place.

### TLDR

- `/planning:interview` Step 2 moves from one-question-at-a-time to **frontier-rounds**: each round asks every question whose prerequisites are settled, numbered, each with a recommendation; answers recompute the frontier; done when frontier is empty.
- Prose is the default question surface; `AskUserQuestion` becomes opt-in via a new planning-plugin `userConfig` boolean (`use_ask_user_question`, default `false`).
- Fact-finding goes non-blocking: facts are dispatched to background sub-agents; only questions downstream of a running lookup wait for it.
- Upstream sharpenings absorbed: facts-vs-decisions split (facts looked up, decisions always put to the user) and an explicit confirmation gate before the Brief locks.
- Question-budget guidance added (depth scales down as upstream artifacts scale up; ballooning frontier routes to `/planning:wayfind`); planning plugin bumps to 0.13.0.

### Goal

An interview session resolves the same decision tree in far fewer round-trips: the user answers a whole frontier of independent questions in one reply (dictation-friendly), dependent questions arrive only after their prerequisites settle, and the terminal "agree, agree, agree" tail collapses into a single round. The skill never asks the user for a fact it can look up, never decides a design choice on the user's behalf, and never acts before the user confirms shared understanding.

### Constraints

- Vocabulary stays "interview" — no "grill/grilling" terminology anywhere in the skill or docs.
- Scope is the interview skill only; other planning skills (prd, design, architect, brainstorm, wayfind) are untouched this change.
- Repo plugin philosophy holds: repo-agnostic, configurable without editing the plugin (`userConfig` for the personal surface preference), plugin-form-safe.
- Cross-skill references stay intra-plugin (wayfind escape valve is a sibling skill in the planning plugin); no new cross-plugin coupling.
- Fresh-docs mandate: the `userConfig` schema is verified from the current plugins docs before the manifest edit lands, not from recall.
- One discipline, not two: rounds everywhere in the skill (`me` and `auto` Q&A); a frontier of one question degenerates to the old behavior, so no per-mode fork.

### Acceptance criteria

- SKILL.md and context/loop.md describe the rounds loop: compute the frontier (all decisions whose prerequisites are settled), ask it as one numbered set in prose with a recommendation per question, wait, recompute; a question dependent on an open question in the same round is deferred to a later round.
- The canonical `me`-mode framing carries the facts-vs-decisions split: facts are resolved from the environment (non-blocking sub-agent dispatch when slow), decisions are always put to the user; the blanket "explore the environment instead of asking" line is gone.
- The stop condition requires an empty frontier AND explicit user confirmation of shared understanding before persistence/handoff.
- `plugins/planning/.claude-plugin/plugin.json` declares `userConfig.use_ask_user_question` (boolean, default `false`); the skill reads `${user_config.use_ask_user_question}` and only uses `AskUserQuestion` when the user opted in.
- gotchas.md, templates/checklist.md, and evals/evals.json are updated — no remaining assertion that questions must be asked one at a time or that batching is a failure mode; evals assert rounds behavior instead.
- Question-budget guidance present: interviews invoked after research/exploration/PRD treat those artifacts as settled prerequisites; a ballooning frontier is named as a `/planning:wayfind` signal; no numeric question cap.
- Planning plugin version is 0.13.0 and CHANGELOG.md carries a behavioral-change note (rounds default, new `question_surface` userConfig).

### Captured assumptions

- ~~Plugin `userConfig` supports a per-user enum/string scalar~~ RESOLVED during planning: plugins-reference fetched this session — no enum type exists; `use_ask_user_question` boolean chosen (see scope-change note); non-sensitive values confirmed substitutable in skill content.
- Upstream `batch-grill-me` is still `in-progress/` and may drift after we ship — acceptable; we own the fork and re-audit upstream opportunistically.

### Out-of-scope

- Rewriting the one-question-at-a-time echoes in prd, design, architect (INTERVIEW tag), and brainstorm — deferred pattern-consistency audit.
- All other upstream ports surfaced by the gap scan (Fowler review baseline, to-questionnaire, skill-quality negation/negative-space, tdd top-up, wayfind task-type verify, git-guardrails, wizard, router) — tracked on the session's deferred agenda, each its own effort.
- A setup action for the surface preference — `userConfig` suffices for V1; setup sugar may follow later.

### Deferred questions

- ~~Exact `question_surface` value set and any additional interview userConfig keys~~ — RESOLVED by /architect: `use_ask_user_question` boolean, default `false` (scope-change note above)
- ~~How an opted-in `AskUserQuestion` surface renders a frontier larger than the tool's 4-question cap~~ — RESOLVED by /architect: prose fallback above 4 or when any same-round dependency exists; no chunking (chunking fragments the round)
- Whether the confirmation gate also applies to `lock`-mode direct synthesis (no Q&A ran) — defer until implementation; **arbiter: USER-RESERVED** (could change the stop-condition contract)

## Plan

**What**: Rewrite `/planning:interview`'s questioning discipline from one-question-at-a-time to frontier-rounds across the skill's five files, declare the `use_ask_user_question` userConfig, bump the planning plugin to 0.13.0.
**Why**: Per the Brief — collapse round-trips (upstream measured 13 rounds → 3 for the same 13 questions), fit dictation workflows, absorb the facts-vs-decisions split and confirmation gate.

### Phase 1: Core discipline rewrite (SKILL.md + context/loop.md) [DONE]

> Execution note (2026-07-17): residue-pattern component `ONE question` proved over-broad case-insensitively (matches the legitimate new template line `Q<N>: <one question>` and "a frontier of one question degenerates"); verified as a separate case-sensitive `grep -En "ONE question"` = 0 instead. Also scrubbed the `:27` "grill me on this decision" override example to interview vocabulary — only the description trigger phrase keeps grill, per the approval carve-out.

| File | Action | What changes |
|------|--------|-------------|
| `plugins/planning/skills/interview/SKILL.md` | Modify | Frontmatter description ("one question at a time, each with a recommendation" → frontier-rounds phrasing). Action Router "Default action leans to `me`" block (:39/:43/:51 including the hyphenated `one-question-at-a-time` at :51) → rounds phrasing. Stance principle 1 → frontier-rounds loop. "NEVER use AskUserQuestion for dependent/sequential" block → new surface rules: prose rounds default; `${user_config.use_ask_user_question}` opt-in; when opted in, AskUserQuestion only for a frontier of ≤4 independent questions, prose fallback above 4 or when any dependency exists. Canonical `me` framing → rounds + facts-vs-decisions split (facts resolved from environment via non-blocking sub-agent dispatch, decisions always to the user). **Disambiguation:** delete ONLY the :78 blanket clause "explore the environment instead of asking"; the :101 "Explore instead of asking" fact-resolution passage is the KEEP half of the split — retitle/reword it as the facts-are-your-job principle, do not delete. Inline question template → round template (numbered set, each question carrying recommendation + alternatives + probe). **Partial-round resolution (new spec):** questions unanswered in a round stay OPEN on the frontier and re-surface at the top of the next round labelled "unanswered from last round" — never silently resolved to the recommendation (auto-guard holds); define accept-shorthands the skill must honor: "accept all recommendations" (whole round) and "yes to N / N–M" (per question). Step 2 summary → compute frontier / ask round / recompute. Step 3 stop condition → empty frontier AND explicit user confirmation of shared understanding (confirmation gate). Question-budget guidance: upstream artifacts (research/explore/PRD) count as settled prerequisites; a ballooning frontier is a `/planning:wayfind` signal; no numeric cap. "Recommended answers" section (:107): update the stale `context/loop.md "Per-round loop" step 4` citation to the renamed loop.md heading. Grill-vocabulary scrub per approval-gate decision (see Handoff): descriptive uses at :3 ("grills relentlessly on request") and :27 ("it grills any plan") → interview vocabulary; the `'grill me'` trigger phrase in the :3 description resolved at the approval gate. |
| `plugins/planning/skills/interview/context/loop.md` | Modify | "Per-round loop" → frontier mechanics (frontier = all decisions whose prerequisites are settled; a question dependent on an open same-round question defers to a later round). `me`-mode mechanics: round format spec, `Q<N>` numbering continues across rounds. "Branch out to ground a recommendation" → non-blocking dispatch semantics (running lookup = unsettled prerequisite; only downstream questions wait). Stop condition + Brief template guidance updated to match. Incremental-persistence discipline unchanged. |

**Sanity Check:** (residue grep is the canonical one, run from repo root; `<residue>` = `one[- ]question[- ]at[- ]a[- ]time|one at a time|one-at-a-time|one-by-one|ONE question`)

- `grep -riEc "<residue>" plugins/planning/skills/interview/SKILL.md plugins/planning/skills/interview/context/loop.md` returns 0 per file
- `grep -c "frontier" plugins/planning/skills/interview/SKILL.md` ≥ 5 and same grep on `context/loop.md` ≥ 5
- `grep -c "explore the environment instead of asking" plugins/planning/skills/interview/SKILL.md plugins/planning/skills/interview/context/loop.md` returns 0 per file, AND the facts-are-your-job principle is present: `grep -ci "facts" plugins/planning/skills/interview/SKILL.md` ≥ 1
- `grep -c "user_config.use_ask_user_question" plugins/planning/skills/interview/SKILL.md` ≥ 1
- `grep -ci "confirm" plugins/planning/skills/interview/SKILL.md` ≥ 1 within the Step 3 stop-condition section (Read assertion)
- `grep -c 'Per-round loop' plugins/planning/skills/interview/SKILL.md` returns 0 (stale citation gone)
- `grep -cwi "grill\|grills\|grilling" plugins/planning/skills/interview/SKILL.md` returns 0 — OR exactly the approved trigger-phrase occurrences if the approval gate keeps `'grill me'` as a trigger

### Phase 2: Satellite surfaces (gotchas, checklist template, evals) [DONE]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/planning/skills/interview/context/gotchas.md` | Modify | Replace "`AskUserQuestion` for sequential decisions" gotcha with two rounds-era gotchas: (1) dependent question asked in the same round as its prerequisite — sloppy frontier computation; (2) `AskUserQuestion` used without the userConfig opt-in or beyond its 4-question cap. Keep all non-cadence gotchas. |
| `plugins/planning/skills/interview/templates/checklist.md` | Modify | Step 2 line → frontier-rounds wording (rounds of settled-prerequisite questions in inline prose; `lock` still synthesizes without Q&A). |
| `plugins/planning/skills/interview/evals/evals.json` | Modify | Four touch-points: (1) eval id `relentless-me-mode-one-at-a-time` — RENAME (e.g. `relentless-me-mode-frontier-rounds`) and flip its expected_output + expectations (":11 asks one question at a time rather than batching" → numbered frontier round of independent questions, each with recommendation); (2) eval id `no-askuserquestion-for-dependent-questions` (:57/:60) — re-scope: dependent decisions are split across rounds (prerequisite first, dependent in a later round), never batched into one round, and AskUserQuestion is not used without the userConfig opt-in; (3) eval id `engineering-term-resolution-delegates` (:81) — replace "resumes the one-question-at-a-time interview" with "resumes the interview at the current round"; (4) ADD one new eval: facts-vs-decisions — a codebase-answerable fact is looked up (not asked) while a genuine design decision is put to the user in the round. |

**Sanity Check:**

- `grep -riEc "<residue>" plugins/planning/skills/interview/context/gotchas.md plugins/planning/skills/interview/templates/checklist.md plugins/planning/skills/interview/evals/evals.json` returns 0 per file (same `<residue>` pattern as Phase 1 — catches the hyphenated forms at gotchas.md:7 and evals.json:81 and the stale eval id name)
- `jq empty plugins/planning/skills/interview/evals/evals.json` exit 0
- eval count = prior count + 1 (`jq` length assertion against the pre-change count captured at implementation start)

### Phase 3: Manifest, userConfig, CHANGELOG [TODO]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/planning/.claude-plugin/plugin.json` | Modify | `version` → `0.13.0`. Add `userConfig.use_ask_user_question`: `{ "type": "boolean", "title": "Use AskUserQuestion for interview rounds", "description": "When enabled, /planning:interview renders a round of up to 4 independent questions through the AskUserQuestion tool instead of inline prose. Default: inline prose (dictation-friendly).", "default": false }`. |
| `plugins/planning/CHANGELOG.md` | Modify | New `## [0.13.0]` entry (Keep a Changelog shape, matching 0.12.0 precedent): Changed — interview questioning discipline is frontier-rounds; Added — `use_ask_user_question` userConfig, facts-vs-decisions split, confirmation gate, question-budget guidance; behavioral-change note for consumers. |

**Sanity Check:**

- `jq -r '.version' plugins/planning/.claude-plugin/plugin.json` = `0.13.0`
- `jq -r '.userConfig.use_ask_user_question.default' plugins/planning/.claude-plugin/plugin.json` = `false`; `.type` = `boolean`; `title` and `description` non-empty (required fields per fetched plugins-reference)
- `claude plugin validate plugins/planning` exit 0 (fallback if CLI unavailable: `jq empty` on the manifest + schema fields present)
- `Get-Content plugins/planning/CHANGELOG.md -TotalCount 8` shows `## [0.13.0]` as the top release entry
- Repo markdown lint passes on all touched `.md` files (project's own lint command per `/toolchain:lint`)

## Test Strategy

Prose/config change — no runtime code, TDD not applicable (explicit carve-out). The test surface is: (1) `evals/evals.json` — updated assertions ARE the behavioral tests, including one new facts-vs-decisions eval; (2) mechanical sanity greps above; (3) `claude plugin validate`; (4) repo markdown lint. Post-merge validation: the next real interview session run under 0.13.0 exercises the discipline live.

## Dependencies

- Depends on: plugins-reference userConfig schema (verified this session — no enum type; boolean chosen); upstream batch-grill-me source (fetched this session).
- Depended on by: the sibling-cadence propagation PR (`.work/upstream-ports/pattern-consistency-audit.md` diffs A–E) — SEPARATE follow-up, applies only after this lands. No marketplace.json version pin exists for planning (verified — no consumer edit needed).

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Sloppy frontier computation asks a dependent question a round early | Med | Low | Named gotcha (Phase 2) + eval asserting cross-round dependency splitting |
| Consumers expecting one-at-a-time are surprised | Med | Low | CHANGELOG behavioral note; frontier of 1 degenerates to old behavior; userConfig opt-out of prose surface |
| Architect/prd/design docs still cite one-at-a-time (stale cross-refs) | High | Low | Known + deliberate: staged diffs in pattern-consistency-audit.md ship as the immediate follow-up PR |
| `${user_config.*}` substitution behavior differs from docs | Low | Med | Verified from live plugins-reference this session (non-sensitive values substitute in skill content); sanity check validates manifest |

## Blast radius

MEDIUM — behavior-visible default change to a flagship skill used across all consumer repos, 7 files, but doc/manifest-only, fully git-revertible, no hooks/CI/enforcement surface, and every semantic decision was user-approved in the interview session (the plan is transcription, not invention). Formal `/devils-advocate` skipped despite MEDIUM: the mandatory fresh-context plan review ran and its findings are fixed; the assumptions a formal pass would attack (rounds model, surface default, config mechanism) were each individually user-ratified during the nine-question interview and field-validated upstream for a week — adversarial re-litigation of human-approved decisions is the anti-pattern the arbiter tags exist to prevent. User may override at the approval gate.

## Stress-test summary

Fresh-context plan reviewer: 0 CRITICAL / 6 IMPORTANT / 2 SUGGESTION — all verified against the files and fixed in this plan: (1) Brief↔Plan key-name contradiction reconciled via dated scope-change note (`question_surface` → `use_ask_user_question`, within deferred-question-1's /architect arbiter grant); (2) partial-round resolution + accept-shorthands specified in Phase 1; (3) Action Router default-leans-`me` block added to the Phase 1 sweep; (4) evals id 7 phrase + id 1 rename + id 5 re-scope added to Phase 2; (5) residue grep broadened to catch hyphenated variants (`<residue>` pattern); (6) grill-vocabulary scrub added — descriptive uses unconditional, trigger phrase gated to user approval; (7) :78-delete vs :101-keep disambiguated; (8) SKILL.md:107 stale citation added to Phase 1. Reviewer confirmed: interview skill has exactly 5 files, all in the edit list; no untouched interview file carries old cadence; manifest shape is schema-correct per live plugins-reference. Formal `/devils-advocate` pass skipped with reason (see Blast radius).

## Execution shape

Fully sequential: Phase 1 → 2 → 3 — Phase 1 defines the vocabulary Phases 2–3 cite; Phase 3's version bump must ride the completed change. All phases main-session (judgment-heavy prose surgery, single semantic thread; no file-disjoint mechanical volume to fan out).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | Core semantic rewrite; every wording choice traces to interview decisions |
| 2 | main-session | Satellites must quote Phase 1's final vocabulary |
| 3 | main-session | Two-file mechanical close-out; not worth a dispatch |

## Open questions

- ~~USER-RESERVED (Brief): does the confirmation gate also apply to `lock`-mode direct synthesis?~~ RESOLVED at approval (2026-07-17): NO — `lock` is exempt; invoking it IS the confirmation. The gate applies to `me`/`auto`; `lock`'s existing STOP-on-gap rule unchanged.
- ~~Grill trigger phrase~~ RESOLVED at approval (2026-07-17): `'grill me'` survives as a trigger phrase ONLY — carved out, ordered LAST in the description's trigger examples (not front-leading); every descriptive/self-referential grill use is scrubbed.

## Handoff to implementation

### User-approval gates

- ~~USER-RESERVED lock-mode question~~ — answered at approval: lock exempt from the confirmation gate.
- ~~Grill-vocabulary scope~~ — answered at approval: descriptive uses scrubbed; `'grill me'` kept as trigger phrase, ordered last in the trigger examples.
- Any mid-flight discovery that changes the Brief's acceptance criteria → stop, chain back to `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential 1→2→3, all main-session (table above).
- [EXEC-SHAPE] `use_ask_user_question` boolean key (schema has no enum type — fetched docs); name/title/description as specified in Phase 3.
- [EXEC-SHAPE] Opted-in AskUserQuestion renders only frontiers of ≤4 independent questions; prose fallback above 4 or when any same-round dependency exists (tool's 4-question cap read from its schema this session).

### Mechanical work

- Branch: `feat/interview-frontier-rounds` off current `origin/main`; Brief + plan commits ride the branch (contract_tier: branch).
- Commit boundaries: one commit per phase; Conventional Commits subjects; CHANGELOG + version bump in the Phase 3 commit.
- Verification: run each phase's Sanity Check before its commit; `/toolchain:lint` on touched markdown before the PR.
- Sequential fallback: n/a (already sequential).
