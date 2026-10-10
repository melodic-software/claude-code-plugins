# Full map — mattpocock/skills (v1.2.3, HEAD 84fdeff, 2026-08-06; v1.3 delta at d81f3a1, 2026-09-29) ↔ melodic-software/claude-code-plugins (main a89a4a33)

> **Correction (2026-08-18, lane 6):** this map's "Claude-only private marketplace"
> characterization (Codex-sidecar row and the marketplace row of the cross-cutting table) was
> stale; the repository is PUBLIC (verified via the repo listing on 2026-08-17 during the
> pocock-course-lanes effort; the row-level notes below carry the same 2026-08-18 correction
> date). The Claude-only part stands; the private part does not. The map is otherwise a
> point-in-time record as of its header date. A separate 2026-08-17 recheck at HEAD `068b6e0`
> found the 35-skill inventory and all relation rows structurally intact (record:
> `aihero-course.md` effort + the pocock-course-lanes contract).

> **v1.3 update (2026-10-04, `pocock-upstream-sync` audit):** at `d81f3a1` the inventory is 37
> skills: Engineering 20 (adds `implement-spec`, `pr` and `retro`, removes
> `resolving-merge-conflicts`), Productivity 7, Misc 4, In-progress 6. That content was untagged
> when audited (version PR #849 open); upstream tagged it v1.3.0 and v1.3.1 on 2026-10-04. The rows
> below keep their v1.2 numbering; the new skills are rows 36-38 in the v1.3 delta section, and
> `CONTEXT.md` / `CONTEXT-MAP.md` are `GLOSSARY.md` / `GLOSSARY-MAP.md` upstream from v1.3
> (`006a52b`, no fallback for the old names).

## Session-start flow and main flow (v1.3.1, rechecked 2026-10-10)

Aligned to the v1.3.1 release (2026-10-04). Upstream `main` is ahead of it at `49dd158` with
unreleased changesets (grilling's yes-accepts wording, wayfinder label and cross-reference fixes,
a handoff temp directory, to-tickets sub-issues); none of them changes the flow below. Since v1.3.0
his skills read and write `GLOSSARY.md` / `GLOSSARY-MAP.md` in place of `CONTEXT.md` /
`CONTEXT-MAP.md`, and `implement-spec`, `pr` and `retro` graduated (rows 36-38).

His session-start rule (X post, 2026-10-08), called the quick-change rule here: a change whose
diff is quick to review and cheap to retry is built in one shot and aligned after the diff is
read; work whose diff fails either test starts with `grill-with-docs`; `wayfinder` is reached only when a grilling session outgrows itself, never as
the first step. His main flow, as `ask-matt` routes it: `grill-with-docs` → `to-spec` →
`to-tickets` → `implement` (or `implement-spec`) → `code-review` → `pr` → `retro`, with triage,
bug diagnosis and wayfinder as on-ramps.

Our decisions, owned by `/session-flow:workflow` and the skills it routes to:

- A quick-to-review, cheap-to-retry change goes straight to implement, then review and verify; the
  two tests decide, not size, and verification rigor stays size-independent. A diff that turns out
  not to be quick to review goes back to the interview.
- New work whose diff fails either test starts with `/planning:interview` (after `/planning:prd`
  when the PRD trigger holds); explore and research are detours the interview triggers.
- `/planning:wayfind` is an escalation from an interview that outgrew one session, and charting
  seeds from that interview's ledger. A brand-new effort is sent to the interview first.
- Our chain: `[/planning:prd →] /planning:interview → [/planning:design →] /planning:plan` →
  `/work-items:decompose` → `/implementation:implement` → review →
  `/source-control:pull-request` → `/session-flow:retro`. Test and verify stay as their own
  stages.

- **Pointer**: when checking the main flow or the on-ramps, fetch
  <https://github.com/mattpocock/skills/blob/main/skills/engineering/ask-matt/SKILL.md> live; when
  checking where wayfinder sits, fetch
  <https://github.com/mattpocock/skills/blob/main/docs/engineering/wayfinder.md> live; correlate
  the session-start rule with <https://x.com/mattpocockuk/status/2108216899439894574>. No docs page
  covers the quick-change rule as of 2026-10-10.
- **As of**: 2026-10-10 (v1.3.1; `main@49dd158`)
- **Recheck trigger**: either recheck event in `mattpocock-skills.md` that touches `ask-matt`,
  `grill-with-docs` or `wayfinder`, or a docs page starting to cover the quick-change rule, at which
  point the pointer moves there.

Sources: his-repo full inventory (35 skills, every SKILL.md read), our-repo provenance sweep (git log + grep + docs), v1.2.0 release notes, v1.2 changelog article, video transcript. As-of 2026-08-08.

Legend — **Relation**: DERIVED (attributed port), PARTIAL (specific ideas taken, attributed), CONVERGENT (same territory, no provenance), NONE (no counterpart). **v1.2+ delta**: what changed upstream since our port / what's new.

## Engineering bucket (18 at v1.2.3; 20 at `d81f3a1`)

| # | His skill | Relation | Ours | What we took / omitted | v1.2+ delta relevant to us |
|---|---|---|---|---|---|
| 1 | `ask-matt` (router) | NONE | no router skill; nearest: `session-flow:workflow` (continuation router), plugin listings | Omitted routing-by-skill; our marketplace is multi-plugin, no single main flow | **Phase-boundaries decision tree** (continue → /clear → /handoff → subagent → /compact; PHASE-BOUNDARIES.md; smart zone ~120k→~150k; "/compact is the default, not the first reach"; "/handoff was oversold — it's for things that travel"). Maps to `session-flow:workflow` + `context-guard` zones |
| 2 | `code-review` | PARTIAL | `review` plugin — code-reviewer agent carries 12-smell Fowler baseline sourced via his PR #464 (re-derived from Fowler primary) | Took: smell baseline concept. ADOPTED, not omitted — an earlier "Omitted" here was wrong: `quality-gate/context/self.md:17` IS that structure ("dispatch two parallel read-only workers … standards conformance vs spec conformance … present them separately"). Only the vocabulary diverges (`lens`, not `axis` — itself the Lane D C13 landing) | Two-axis kept upstream; "repo overrides" + "never merge/rerank the two axes" framing. v1.2.3: harness-neutral subagent language |
| 3 | `codebase-design` | DERIVED (corrected 2026-10-04 from CONVERGENT) | `architecture:improve`, `naming` plugin territory | Ported, not "not ported": the vocabulary below sits near word for word in `architecture/skills/improve/research/deepening/vocabulary.md:9-30` since `30cf0343f` (2026-07-10); SSOT attribution row. Upstream issues #449, #458 (open). Deep-module vocabulary (Module/Interface/Depth/Seam/Adapter/Leverage/Locality + deletion test, "one adapter = hypothetical seam, two = real") | Absorbed `design-an-interface` as `DESIGN-IT-TWICE.md` (parallel sub-agents produce radically different designs — Ousterhout). Vocabulary could enrich architecture/naming skills |
| 4 | `diagnosing-bugs` | PARTIAL | `debugging:debug`, `testing:diagnose` | **PARTIAL, not "not ported" (relation corrected 2026-08-21):** the v1.2.3 redaction guard and the `[DEBUG-a4f2]` tagged-log convention were both ADOPTED into `debugging:debug` and `testing:diagnose` (SSOT attribution row). Still not taken: feedback-loop-first doctrine ("build the loop and the bug is 90% fixed"), 10 ranked loop types, 3–5 ranked hypotheses | **v1.2.3 Redact section** — discharged: the guard landed in both skills (secrets `<REDACTED>` before any shown command, output, or artifact). v1.3: Phase 6 post-mortem hand-off removed (`1dab982`); we keep ours (SSOT row). Upstream PR #1121 (released v1.3.1) sends the post-bug question to `retro`; issue #1117 closed by it. Gaps under evaluation: the minimize step and the Phase 1 completion criterion; the ranked loop types and hypotheses are already present (`debug/SKILL.md:61-72`, `:112-122`) |
| 5 | `domain-modeling` | PARTIAL | `domain-driven-design:curate-language`; ADR 3-gate + glossary purity guard live in `planning:interview` (grilling-family absorb #163) | Took: ADR 3-gate (hard-to-reverse ∧ surprising ∧ real trade-off), glossary purity. Omitted: the fixed glossary file convention (`CONTEXT.md`/`CONTEXT-MAP.md` at v1.2.3, `GLOSSARY.md`/`GLOSSARY-MAP.md` from v1.3; ours format-externalized) | Absorbed `ubiquitous-language`. "Create files lazily"; `GLOSSARY.md` = glossary and nothing else (was `CONTEXT.md`). v1.3 trigger: discussing codebase terminology, or writing a `GLOSSARY.md` or an ADR (#848). Ours already satisfies open request #557 (decouple ADRs from domain modeling): `curate-language` owns no ADRs (`SKILL.md:107-108`). Watch #717 (cross-reference the tracker when resolving a term) and #1153 (the rename has no migration path) |
| 6 | `grill-with-docs` | PARTIAL | `planning:interview` engineering mode (domain-routing absorb) | Took: primitive-vs-variant boundary. His is a 1-line wrapper, at v1.3: "Call the Skill tool twice, for "grilling" and "domain-modeling"" (was "Run /grilling using /domain-modeling") | Now runs frontier rounds (we already have rounds). v1.3 reads and writes `GLOSSARY.md` |
| 7 | `implement` | CONVERGENT | `implementation:implement` (far larger) | Not ported; his is 5 lines (tdd at pre-agreed seams, typecheck regularly, code-review at end, commit) | v1.3: skill unchanged; its docs page sends parallel or whole-spec runs to `implement-spec` (`docs/engineering/implement.md:55-57`) and the main chain now ends `→ retro` (`:90`). Maintainer on closed issue #906: a material decision found mid-implement "should be a user decision", which matches our divergence ladder |
| 8 | `improve-codebase-architecture` | PARTIAL | `architecture:improve` (domain-routing absorb touched it) | Took: the HTML report (temp-dir, self-contained, three badges; `actions/deepening.md:66-85`). Omitted: its CDN Tailwind and Mermaid loading. Corrected 2026-10-04: this cell said the HTML report was omitted and "grilling integration" taken; the report was adopted, and no grilling integration exists (the deepening interview runs its own loop and calls only `curate-language`). v1.3 removed the inbound `diagnosing-bugs` hand-off (`1dab982`) | **YAGNI scoping filter** (#533): named direction, else last ~20 commit messages bias exploration to hot paths — direct candidate for `architecture:improve` |
| 9 | `prototype` | PARTIAL | `prototype:explore-directions`, `prototype:pressure-test` | **PARTIAL, not "not ported" (relation corrected 2026-08-21):** the two skills predate/parallel his, but the `LOGIC.md` shareable-HTML demo shell was ADOPTED into `prototype:pressure-test` in lane 5 — audience-routed, with the TUI still the default (SSOT attribution row) | **Single self-contained shareable HTML file** (non-developer double-clicks; state panel, free-play, tabbed guided walkthroughs); **prototype captured as primary source on `prototype/<name>` branch** with context pointer on the implementation issue |
| 10 | `research` | CONVERGENT | `discovery:research` (far heavier: tiers, ledger, outcome gate) | Not ported; his is 3 bullets (background agent, primary sources, save per repo convention) | Upstream failure reports, open as of 2026-10-04: #530 (a spawned background agent can re-spawn another, unbounded), #576 (wayfinder research tickets open draft PRs), #995 (over-triggers on ordinary lookups) |
| 11 | `resolving-merge-conflicts` | DERIVED (corrected 2026-10-04 from CONVERGENT) | `source-control:resolve-conflicts` | Ported, not "not ported": PR #200 (`2ebc55db1`, 2026-07-15, branch `absorb/pocock-mechanisms`) added ours after his skill existed, and his 5 steps map one to one. NOTE: the stranded local branch of the same name held a resolve-conflicts evals variant, deliberately excluded (#1400). Kept pending an eval (SSOT row) | **Removed upstream in v1.3** (`daa01d8aa68ad5c61b68970ec2018d0ce9567be6`): "nothing replaces it"; out of the README, `plugin.json` and the ask-matt router; docs page kept, marked archived. His 5 steps incl. "always resolve; never --abort" |
| 12 | `setup-matt-pocock-skills` | NONE | no analog — our plugins configure via `userConfig` + consumer CLAUDE.md instead of a setup interview | Omitted deliberately (different distribution model) | #502: friendlier (recommended-yes, monorepo signals, `.scratch/<feature>/issues/<NN>-<slug>.md`, `spec.md`). v1.3: domain-docs layout is `GLOSSARY.md` (or a root `GLOSSARY-MAP.md` for multi-context) plus `docs/adr/`; other skills now tell the user to run it instead of calling it (`1dab982`) |
| 13 | `tdd` | PARTIAL | `tdd:principles`, `testing:write` | **PARTIAL, relocated** (Lane C C9 — verdict token corrected 2026-08-21 from "ADOPTED-ADAPTED" to the course SSOT's wording, which owns lane verdicts), not "not ported": the seam discipline landed at `plugins/planning/skills/plan/SKILL.md:183` (line re-checked 2026-10-04) as a named test-boundary element, with two deliberate divergences — "seam" avoided (fleet-registered vocabulary) and the hard consent gate softened to a `DEVIATIONS.md` record an unattended run can actually satisfy | Seam discipline ("no test at an unconfirmed seam"), 3 anti-patterns (implementation-coupled, tautological, horizontal-slicing/tracer bullets), "refactoring is not part of the loop" |
| 14 | `to-spec` | PARTIAL | `planning:prd`/`planning:plan` + interview Brief | **PARTIAL** (relation column corrected 2026-08-21 to match what this cell already said), not "not ported": C3 landed as the optional `## Testing decisions` section (now `decompose/context/container-lifecycle.md:31`) and C4 as the whole spec-on-tracker container lifecycle (moved to that file; pointer at `decompose/SKILL.md:192-197`). Still not taken: extensive user stories. Corrected 2026-10-04: no-interview pure synthesis is ALREADY-PRESENT (SSOT `to-spec` row, C1) and "no file paths" is in our slice template (`decompose/SKILL.md:169`) | `/to-prd`→`/to-spec` rename FINISHED (A9); spec file = `spec.md`; fewest-seams-possible doctrine |
| 15 | `to-tickets` | PARTIAL | `work-items:decompose` (course "tickets" absorbed as canonical "work items"; ticket/issue are invocation synonyms, not a rename) | Vertical-slice / tracer-bullet vocabulary overlap recorded as influence. **expand–contract** wide-refactor exception already on our decompose (`SKILL.md` §2b) | One-file-per-ticket local layout (ALREADY-PRESENT, closed 2026-10-04: our `local-markdown` tracker adapter keeps one markdown file per item, `adapters/local-markdown/README.md:25`); **expand–contract** wide-refactor exception; "work the frontier" |
| 16 | `triage` | DERIVED | `work-items:triage` (our surface; "a PR is an item with attached code" ≈ course/skills "a PR is an issue with attached code") | Structured `.out-of-scope/` KB port recorded on the skills-repo SSOT (already-adopted; v1.2 M15 rejected as duplicate) | **`.out-of-scope/` KB** already adopted (SSOT triage row); mandatory AI-generated disclaimer on posted comments |
| 17 | `wayfinder` | PARTIAL | `planning:wayfind` (`wayfinder` → `wayfind`; fog-of-war + ticket-vs-fog attributed; tracker-native map ours) | Relation corrected 2026-08-21 DERIVED → PARTIAL, matching the SSOT attribution row and this map's own legend — `planning:wayfind` is not a port of his artifact, it is our surface with specific ideas taken and attributed (the `wayfinder` → `wayfind` name is the derived part). Took: fog framing, ticket-vs-fog test. Rejected: file-based map, his tracker seam. Decision tickets → tracker-native decision items / work-map (work-items vocabulary) | **Decision-ticket term** maps to our "decision item" / work-map (not CONTEXT.md files); **research tickets burned down in parallel via /research subagents on `research/<name>` branch** (exception to one-ticket-per-session; `research/<name>` branch REJECTED on SSOT); over-reach warning (well-scoped feature → grill, not wayfind); "when the map clears it hands off — merge at /to-spec" |
| 18 | `wizard` | DERIVED (lane 4) | `wizard:generate` — new single-capability plugin `wizard` 0.1.0 | PORTED (hardened): 4-step process, fixed library above STAGES marker, model-invoked + non-trigger fence, gh graceful degradation, ephemeral-by-default kept; hardened with human STAGES approval before `chmod +x`, https-only open_url, `/dev/tty` fail-closed prompts, quoted 0600 `.env` writes + gitignore assert, repo-confirmed `--repo`-explicit gh writes, key-name validation, readline non-secret asks (#741), names-only live-`.env` scoping + honest secrets-context prose. Codex sidecar not ported. SSOT row + `plugins/wizard/CHANGELOG.md` carry provenance | **NEW graduate**, model-invoked. Interactive bash wizard for human-only steps; fixed `template.sh` library above STAGES marker (never hand-edited); deterministic = secrets never reach agent; 4 trigger branches + explicit non-trigger; verify via `bash -n` + shellcheck; v1.2.3 dropped time estimates |

## Productivity bucket (7)

| # | His skill | Relation | Ours | Notes | v1.2+ delta |
|---|---|---|---|---|---|
| 19 | `grill-me` | DERIVED (behavior) | `planning:interview` frontier-rounds (#278 cites batch-grill-me; propagated to prd/design/plan #294) | Ours: no-grill vocabulary constraint; prose default + AskUserQuestion opt-in; background fact sub-agents; ballooning-frontier → wayfind route | Rounds now upstream-mainline in `grilling`; fixed ❓/➡️ emoji shape + answer-by-number dictation affordance; opt-out line in global CLAUDE.md. We already have the substance — delta is presentational. v1.3: the `grill-me` body is one line calling the Skill tool with `grilling` |
| 20 | `grilling` | PARTIAL | `planning:interview` core loop | Domain-generalization (#532 reword) already mirrored by our domain-routing | v1.3: a `---` rule between questions in a round (`85f83d3`), REJECTED as cosmetic (`aihero-course.md` lane 5) |
| 21 | `handoff` | PARTIAL | `session-flow:handoff` (claim-provenance + constraint re-scan mined from his issues #186/#306/#617/#482) | Ours far larger (save-point files, find-handoff, reconcile) | ask-matt reframes: handoff is NARROW (only when something travels); ours already richer but framing worth comparing |
| 22 | `teach` | DERIVED | `education:teach` (siblings: `education:explain`, `education:quiz-me`) | CORRECTED from CONVERGENT by the `teach-skill-comparison` topic audit: the original port took his workspace vocabulary (MISSION.md, learning records as "teaching ADRs"), near-verbatim FORMAT content, and K-S-W/ZPD pedagogy; storage-strength pedagogy, HTML-first lessons, and the `assets/` library re-adopted in education 0.7.0. Full taken/rejected/added record: mattpocock-skills.md attribution table | — |
| 23 | `to-questionnaire` | DERIVED | `planning:questionnaire` (#311) | Ours: interview-the-send invariant kept; output relocated cwd → memory slice (PII); tracker item; interview vocabulary | **Graduated in-progress → Productivity** (#593). Our provenance line said "in-progress": discharged, the line was removed (finding 1 below). ask-matt routes it as inverse of grill-me |
| 24 | `wait-what` | DERIVED (lane 3) | `discipline:wait-what` (ported near-verbatim; declared non-corrector species). Lane-3 vetting corrected the adjacency: true nearest neighbors are `education:explain` (altitude) + `adhd:clarify` (structure) — this fills the third cell (precision-keeping re-pitch); `tighten-your-output`/`caveman` are output-shape (the failure register), `curate-language` owns glossary writes | — | **NEW** (#751). One-sentence user-invoked corrective (8-line file): re-pitch w/ context + ASD-STE100 + ubiquitous language from `GLOSSARY.md` at v1.3, following `GLOSSARY-MAP.md` to the right one (was `CONTEXT.md` at v1.2.3). Name-as-mechanism doctrine (listener's state, not output shape). STE-100 verified real (Issue 9, 2025, 53 rules/900 words). Port record: SSOT row + PLAN.md `### Lane 3` |
| 25 | `writing-for-agents` | PARTIAL | `playbooks:skill-authoring`, `docs-hygiene:*` (audit-noise, audit-derivability, extract-ssot, compress), `skill-quality:check` | **PARTIAL, not "not ported" (relation corrected 2026-08-21):** the leading-words/negation half landed as `docs-hygiene:write-for-agents` § "Prompt the positive" (0.17.0, [#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962)), retiring that tracked strand on the SSOT. **Re-evaluated 2026-08-17** (steering-section session): parity holds only on the pruning/audit half; authoring-side gaps (authoring-time trigger, completion criteria, invocation-choice doctrine) tracked as course lanes 7–8 ([#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909), [#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910)) — section-by-section verdicts in the SSOT decomposition table | **Breaking rename** from writing-great-skills; scope = any agent-consumed doc; GLOSSARY merged in; SKILL-MECHANICS.md split out; model-invoked (v1.2.2: Codex sidecar policy line REMOVED so it stays model-invocable there); **"cache" pruning term** (environment is SSOT; doc restating it = cache, earns load only when lookup expensive) ≈ our audit-derivability; leading words, negation warning, two loads, information hierarchy |

## Misc bucket (4, not in plugin)

| # | His | Relation | Ours | Notes |
|---|---|---|---|---|
| 26 | `git-guardrails-claude-code` | DERIVED (capability) | `guardrails` block-dangerous-git hook (#298) | Implementation rejected wholesale — his substring matcher false-blocks; ours argv-grammar parser (190 tests at introduction, 278 at current main). Unchanged upstream in v1.2 |
| 27 | `migrate-to-shoehorn` | NONE | — | TS/personal tooling; correctly omitted |
| 28 | `scaffold-exercises` | NONE | — | AI-Hero-internal; correctly omitted |
| 29 | `setup-pre-commit` | NONE | — (toolchain/repo-hygiene territory) | Husky/lint-staged setup; low value for us |

## In-progress bucket (6, beta)

| # | His | Relation | Ours | Notes |
|---|---|---|---|---|
| 30 | `claude-handoff` | PARTIAL | `session-flow:continue-in-background`; handoff `--bg` (#76 cites pocock-v11 slice) | Same idea: handoff → background agent (`claude --bg --name`). Draft upstream PR #647 would rename it `spawn` and add other agents' CLIs; still an open draft on 2026-10-04 |
| 31 | `loop-me` | CONVERGENT | `claude-code-setup:claude-automation-recommender`, `/loop`, `work-items` | Life-loops → workflow specs; push-right checkpoint doctrine; beta — watch |
| 32 | `setup-ts-deep-modules` | NONE | `review:architecture-guardian` (review-time vs his build-time dependency-cruiser enforcement); `review:audit-enforceability` (its architecture-test rung names dependency-cruiser) | TS-specific; beta; interesting completion criterion ("prove the rules bite": pass→fail→pass) |
| 33–35 | `writing-beats` / `writing-fragments` / `writing-shape` | NONE | — | Human-writing workflow (explore/exploit split, beats, grounding); out of our marketplace's scope so far |

## v1.3 delta: new Engineering skills at `d81f3a1`

Graduated in v1.3 (untagged when audited; tagged v1.3.0 on 2026-10-04). Row 11
(`resolving-merge-conflicts`) left the Engineering bucket in the same release. Taken/rejected
detail lives in the SSOT attribution rows; nothing here is adopted yet.

| # | His skill | Relation | Ours | What we took / omitted | v1.3 notes |
|---|---|---|---|---|---|
| 36 | `implement-spec` (user-invoked) | CONVERGENT / PARTIAL | `implementation:implement-dispatch`; `work-items:ship` integration-branch execution shape (sequential, operator-driven) | Nothing taken. Candidates under evaluation: red-run evidence from dispatched workers, a worktree-base check before the first edit. Parallel executor TRACKED | Runs a spec's ready frontier in one run: worktree per ticket, one integration branch, final `code-review`. Open defect #936 (the frontier cannot advance mid-run) |
| 37 | `pr` (model-invoked) | CONVERGENT (PARTIAL) | `source-control:pull-request` body contract; `visualization:visualize` code shapes; merge-lane door test | Same humanlayer `show-me` menu reached us directly (`humanlayer-skills.md`). Body template REJECTED (drops our required sections). Door/blast-radius body line under evaluation | Summary as the smallest visual, before/after evidence, one-way or two-way door plus blast radius |
| 38 | `retro` (user-invoked) | CONVERGENT | `session-flow:retro`, `session-flow:running-retro` (ours predates his) | Nothing taken. Candidates under evaluation: deterministic-check route, removal pass for contradicted rules, skill edits through the approval gate; upstream-report-only ideas go eval-first | Seven categories (Navigation, Automated checks, Coding standards, Global AGENTS.md, Tool economy, No-ops, Information access); last step of his main chain; #1121 (v1.3.1) routes post-bug reflection to it |

## Cross-cutting v1.2 infrastructure (not per-skill)

| Item | His v1.2 | Ours | Assessment |
|---|---|---|---|
| Codex `agents/openai.yaml` sidecars | Every skill; `allow_implicit_invocation: false` mirrors `disable-model-invocation`; v1.2.2 lesson: policy line on a model-invoked skill HIDES it in Codex | None (Claude-only marketplace; the repo itself is PUBLIC — "private marketplace" here was stale, corrected 2026-08-18 by lane 6) | Corrected 2026-10-04: not N/A. Codex reads `.claude-plugin/` manifests, so a Codex user can install this marketplace without us targeting it, and there our 75 user-invoked skills are model-reachable; Copilot CLI hides them even when typed. The maintainer says the sidecars are what make his skills work in Codex (upstream #178). Evidence and the TRACK decision: SSOT Harness findings |
| Claude Code plugin + official marketplace | `claude plugins install mattpocock-skills`; sha-pinned listing; read-only bundle | We ARE a marketplace already (public repo; "private" was stale — lane 6 correction, 2026-08-18) | Parity; his ADR 0002 (Codex plugin deferred: single-path `skills` string + symlink-dropping cache) is reference material, but its Codex premise is stale: a 2026-07-21 comment on upstream PR #565 reports Codex accepts array manifest paths since v0.142.0, and draft PR #807's ADR 0003 would supersede ADR 0002 in part |
| Docs site (aihero.dev/skills) | Per-skill pages, Common questions from real-question wiki, "It's working if" sections, dictionary term links | `docs/` + per-plugin READMEs; no per-skill site | "It's working if" = completion-criteria-for-humans; nice pattern |
| `AGENTS.md` symlink → `CLAUDE.md` | symlink (materializes as plain text on Windows checkouts!) | our CLAUDE.md `@AGENTS.md` import | Ours is Windows-safe; his breaks on Windows — no action |
| Changesets + `sync-plugin-version.mjs` (`--check` drift gate) | package.json ↔ plugin.json version sync enforced | Per-PR manual semver per plugin CHANGELOG today; [ADR 0048](../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md) (accepted 2026-10-03, not yet built) adopts the changesets model: changelog fragments with a bump level, one bot-maintained release PR | Drift-check idea portable to our marketplace lint |
| Buckets: promoted/in-progress(beta)/misc/deprecated(empty—retired=deleted, changeset names replacement) | | Plugins as units; no beta channel | Beta-channel concept interesting. Corrected 2026-10-04: the v1.3 removal changeset for `resolving-merge-conflicts` says nothing replaces it, although `skills/deprecated/README.md` still says the removing changeset names the replacement, and a removed promoted skill keeps an archived docs page (`.agents/writing-docs.md:7`). Draft PR #807 (flatten `skills/` for Agent Plugins 1.0) would restructure the buckets; recheck the bucket names if it merges |
| User-invoked reachability rule | "A user-invoked skill may invoke model-invoked skills, but never another user-invoked skill" | STATED — `docs/conventions/invocation-mode/README.md:64` is a section headed "The invocation-reach invariant", restated at `plugins/playbooks/skills/skill-authoring/SKILL.md:180-182`. The "no such invariant" claim also contradicted this file's own sibling SSOT, which records it CONFIRMED | Already landed; no action |
| Smart zone ~150k | ask-matt | `context-guard` bands (zone thresholds) | Compare our band figures against 150k claim |
| Upstream issue #693 | Desktop/web surfaces drop user-invoked skills from listing | Affects OUR user-invoked skills too on those surfaces | Recheck trigger candidate |

## Drift/fix findings (our repo, regardless of integration decisions)

> **Lane-1 resolution (2026-08-08):** findings 1 and 2 fixed — provenance moved out of skill
> bodies into `docs/upstream/mattpocock-skills.md` (which carries the observable recheck
> trigger). Finding 3 resolved as
> "influence, recorded": the SSOT attribution table names both work-items skills. Finding 4 is
> the standing audit baseline (SSOT then recorded v1.2.3 @ `84fdeff`; since 2026-10-04 it records
> the v1.3 content at `d81f3a1`).

1. **DISCHARGED (verified 2026-08-21) — the cited lines no longer exist.** `questionnaire/SKILL.md` is 45 lines and greps clean for `to-questionnaire`, `in-progress`, `pocock`, `upstream` and `opportunistic`; the line was removed 2026-08-09 in `03a827f9` (#2082), BEFORE this map was written. The original finding read: `plugins/planning/skills/questionnaire/SKILL.md:48-50` says upstream `to-questionnaire` is "in-progress" — it graduated to Productivity in v1.2.0 (#593). The skill-body provenance-line fix is planning-owned (serialized with #2938/#2939), not this PR (#2947).
2. **DISCHARGED with finding 1 — same removed lines.** Original finding: "re-audit opportunistically" (questionnaire SKILL.md:50, planning CHANGELOG:562) fails `docs/conventions/upstream-drift/README.md` observability bar — no observable event. The guardrails attribution (`plugins/guardrails/CHANGELOG.md:~1783`) carries NO re-audit trigger at all. Candidate trigger: "a mattpocock/skills release whose changeset names <upstream skill>". [verifier-corrected]
3. **HONESTY FLAG** (resolved — influence, recorded): `work-items:triage` ("a PR is an item with attached code") and `work-items:decompose` (vertical-slice/tracer-bullet) carry near-verbatim Pocock phrasings. Decision landed in #2947: SSOT attribution table + map rows 15–16 (`to-tickets` PARTIAL, `triage` DERIVED) now carry the provenance record.
4. His repo HEAD is v1.2.3, not v1.2.0 — any sync should target HEAD (Redact section, harness-neutral dispatch, wizard sans time-estimates, writing-for-agents Codex-sidecar fix).
5. **OVERSTATED PARITY** (found 2026-08-17, steering-section session): the lane-5 rejection of `writing-for-agents` "at parity or stronger" covered only the pruning/audit half; the completion-criteria section was unmapped and unrecorded, and no authoring-time surface exists for non-skill agent docs. Corrected in the SSOT (decomposition section); gaps tracked as [#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909)/[#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910). [resolved 2026-08-17 — doc correction landed; substance rides the lane issues]
