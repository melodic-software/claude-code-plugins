# Full map — mattpocock/skills (v1.2.3, HEAD 84fdeff, 2026-08-06) ↔ melodic-software/claude-code-plugins (main a89a4a33)

Sources: his-repo full inventory (35 skills, every SKILL.md read), our-repo provenance sweep (git log + grep + docs), v1.2.0 release notes, v1.2 changelog article, video transcript. As-of 2026-08-08.

Legend — **Relation**: DERIVED (attributed port), PARTIAL (specific ideas taken, attributed), CONVERGENT (same territory, no provenance), NONE (no counterpart). **v1.2+ delta**: what changed upstream since our port / what's new.

## Engineering bucket (18)

| # | His skill | Relation | Ours | What we took / omitted | v1.2+ delta relevant to us |
|---|---|---|---|---|---|
| 1 | `ask-matt` (router) | NONE | no router skill; nearest: `session-flow:workflow` (continuation router), plugin listings | Omitted routing-by-skill; our marketplace is multi-plugin, no single main flow | **Phase-boundaries decision tree** (continue → /clear → /handoff → subagent → /compact; PHASE-BOUNDARIES.md; smart zone ~120k→~150k; "/compact is the default, not the first reach"; "/handoff was oversold — it's for things that travel"). Maps to `session-flow:workflow` + `context-guard` zones |
| 2 | `code-review` | PARTIAL | `review` plugin — code-reviewer agent carries 12-smell Fowler baseline sourced via his PR #464 (re-derived from Fowler primary) | Took: smell baseline concept. Omitted: his two-axis Standards/Spec parallel-subagent structure (ours: fanout + quality-gate modes) | Two-axis kept upstream; "repo overrides" + "never merge/rerank the two axes" framing. v1.2.3: harness-neutral subagent language |
| 3 | `codebase-design` | CONVERGENT | `architecture:improve`, `naming` plugin territory | Not ported. Deep-module vocabulary (Module/Interface/Depth/Seam/Adapter/Leverage/Locality + deletion test, "one adapter = hypothetical seam, two = real") | Absorbed `design-an-interface` as `DESIGN-IT-TWICE.md` (parallel sub-agents produce radically different designs — Ousterhout). Vocabulary could enrich architecture/naming skills |
| 4 | `diagnosing-bugs` | CONVERGENT | `debugging:debug`, `testing:diagnose` | Not ported. His: feedback-loop-first doctrine ("build the loop and the bug is 90% fixed"), 10 ranked loop types, 3–5 ranked hypotheses, `[DEBUG-a4f2]` tagged logs | **v1.2.3 adds Redact section** (secrets in debug output) — check our debugging skill for equivalent guard |
| 5 | `domain-modeling` | PARTIAL | `domain-driven-design:curate-language`; ADR 3-gate + glossary purity guard live in `planning:interview` (grilling-family absorb #163) | Took: ADR 3-gate (hard-to-reverse ∧ surprising ∧ real trade-off), glossary purity. Omitted: CONTEXT.md/CONTEXT-MAP.md file convention (ours format-externalized) | Absorbed `ubiquitous-language`. "Create files lazily"; CONTEXT.md = glossary and nothing else |
| 6 | `grill-with-docs` | PARTIAL | `planning:interview` engineering mode (domain-routing absorb) | Took: primitive-vs-variant boundary. His is a 1-line wrapper: "Run /grilling using /domain-modeling" | Now runs frontier rounds (we already have rounds) |
| 7 | `implement` | CONVERGENT | `implementation:implement` (far larger) | Not ported; his is 5 lines (tdd at pre-agreed seams, typecheck regularly, code-review at end, commit) | — |
| 8 | `improve-codebase-architecture` | PARTIAL | `architecture:improve` (domain-routing absorb touched it) | Took: grilling integration. Omitted: HTML report (temp-dir, Tailwind+Mermaid, badges) | **YAGNI scoping filter** (#533): named direction, else last ~20 commit messages bias exploration to hot paths — direct candidate for `architecture:improve` |
| 9 | `prototype` | CONVERGENT | `prototype:explore-directions`, `prototype:pressure-test` | Not ported (ours predates/parallel) | **Single self-contained shareable HTML file** (non-developer double-clicks; state panel, free-play, tabbed guided walkthroughs); **prototype captured as primary source on `prototype/<name>` branch** with context pointer on the implementation issue |
| 10 | `research` | CONVERGENT | `discovery:research` (far heavier: tiers, ledger, outcome gate) | Not ported; his is 3 bullets (background agent, primary sources, save per repo convention) | — |
| 11 | `resolving-merge-conflicts` | CONVERGENT | `source-control:resolve-conflicts` | Not ported. NOTE: stranded local branch `absorb/pocock-mechanisms` held a resolve-conflicts evals variant, deliberately excluded (#1400) | Now in ask-matt router. His 5 steps incl. "always resolve; never --abort" |
| 12 | `setup-matt-pocock-skills` | NONE | no analog — our plugins configure via `userConfig` + consumer CLAUDE.md instead of a setup interview | Omitted deliberately (different distribution model) | #502: friendlier (recommended-yes, monorepo signals, `.scratch/<feature>/issues/<NN>-<slug>.md`, `spec.md`) |
| 13 | `tdd` | CONVERGENT | `tdd:principles`, `testing:write` | Not ported. Deferred-ports ledger names "tdd top-up" (never shipped) | Seam discipline ("no test at an unconfirmed seam"), 3 anti-patterns (implementation-coupled, tautological, horizontal-slicing/tracer bullets), "refactoring is not part of the loop" |
| 14 | `to-spec` | CONVERGENT | `planning:prd`/`planning:plan` + interview Brief | Not ported. His: no interview, pure synthesis; extensive user stories; no file paths in specs | `/to-prd`→`/to-spec` rename FINISHED (A9); spec file = `spec.md`; fewest-seams-possible doctrine |
| 15 | `to-tickets` | CONVERGENT | `work-items:decompose` (vertical-slice/tracer-bullet vocabulary near-identical) | No provenance recorded, but vocabulary overlap is striking — flag for honesty check | One-file-per-ticket local layout; **expand–contract** wide-refactor exception; "work the frontier" |
| 16 | `triage` | CONVERGENT | `work-items:triage` (state machine; our listing "a PR is an item with attached code" ≈ his "a PR is an issue with attached code" — flag) | No provenance recorded | **`.out-of-scope/` KB** (prior-rejection institutional memory, dedupe check) — candidate; mandatory AI-generated disclaimer on posted comments |
| 17 | `wayfinder` | DERIVED | `planning:wayfind` (fog-of-war + ticket-vs-fog attributed; tracker-native map ours) | Took: fog framing, ticket-vs-fog test. Rejected: file-based map, his tracker seam | **Decision-ticket term** (CONTEXT.md domain term); **research tickets burned down in parallel via /research subagents on `research/<name>` branch** (exception to one-ticket-per-session); over-reach warning (well-scoped feature → grill, not wayfind); "when the map clears it hands off — merge at /to-spec" |
| 18 | `wizard` | DERIVED (lane 4) | `wizard:generate` — new single-capability plugin `wizard` 0.1.0 | PORTED (hardened): 4-step process, fixed library above STAGES marker, model-invoked + non-trigger fence, gh graceful degradation, ephemeral-by-default kept; hardened with human STAGES approval before `chmod +x`, https-only open_url, `/dev/tty` fail-closed prompts, quoted 0600 `.env` writes + gitignore assert, repo-confirmed `--repo`-explicit gh writes, key-name validation, readline non-secret asks (#741), names-only live-`.env` scoping + honest secrets-context prose. Codex sidecar not ported. SSOT row + `plugins/wizard/CHANGELOG.md` carry provenance | **NEW graduate**, model-invoked. Interactive bash wizard for human-only steps; fixed `template.sh` library above STAGES marker (never hand-edited); deterministic = secrets never reach agent; 4 trigger branches + explicit non-trigger; verify via `bash -n` + shellcheck; v1.2.3 dropped time estimates |

## Productivity bucket (7)

| # | His skill | Relation | Ours | Notes | v1.2+ delta |
|---|---|---|---|---|---|
| 19 | `grill-me` | DERIVED (behavior) | `planning:interview` frontier-rounds (#278 cites batch-grill-me; propagated to prd/design/plan #294) | Ours: no-grill vocabulary constraint; prose default + AskUserQuestion opt-in; background fact sub-agents; ballooning-frontier → wayfind route | Rounds now upstream-mainline in `grilling`; fixed ❓/➡️ emoji shape + answer-by-number dictation affordance; opt-out line in global CLAUDE.md. We already have the substance — delta is presentational |
| 20 | `grilling` | PARTIAL | `planning:interview` core loop | Domain-generalization (#532 reword) already mirrored by our domain-routing | — |
| 21 | `handoff` | PARTIAL | `session-flow:handoff` (claim-provenance + constraint re-scan mined from his issues #186/#306/#617/#482) | Ours far larger (save-point files, find-handoff, reconcile) | ask-matt reframes: handoff is NARROW (only when something travels); ours already richer but framing worth comparing |
| 22 | `teach` | DERIVED | `education:teach` (siblings: `education:explain`, `education:quiz-me`) | CORRECTED from CONVERGENT by the `teach-skill-comparison` topic audit: the original port took his workspace vocabulary (MISSION.md, learning records as "teaching ADRs"), near-verbatim FORMAT content, and K-S-W/ZPD pedagogy; storage-strength pedagogy, HTML-first lessons, and the `assets/` library re-adopted in education 0.7.0. Full taken/rejected/added record: mattpocock-skills.md attribution table | — |
| 23 | `to-questionnaire` | DERIVED | `planning:questionnaire` (#311) | Ours: interview-the-send invariant kept; output relocated cwd → memory slice (PII); tracker item; interview vocabulary | **Graduated in-progress → Productivity** (#593). Our provenance line still says "in-progress" — STALE, fix. ask-matt routes it as inverse of grill-me |
| 24 | `wait-what` | DERIVED (lane 3) | `discipline:wait-what` (ported near-verbatim; declared non-corrector species). Lane-3 vetting corrected the adjacency: true nearest neighbors are `education:explain` (altitude) + `adhd:clarify` (structure) — this fills the third cell (precision-keeping re-pitch); `tighten-your-output`/`caveman` are output-shape (the failure register), `curate-language` owns glossary writes | — | **NEW** (#751). One-sentence user-invoked corrective (8-line file): re-pitch w/ context + ASD-STE100 + CONTEXT.md ubiquitous language. Name-as-mechanism doctrine (listener's state, not output shape). STE-100 verified real (Issue 9, 2025, 53 rules/900 words). Port record: SSOT row + PLAN.md `### Lane 3` |
| 25 | `writing-for-agents` | CONVERGENT | `playbooks:skill-authoring`, `docs-hygiene:*` (audit-noise, audit-derivability, extract-ssot, compress), `skill-quality:check` | Not ported; strongly parallel doctrine | **Breaking rename** from writing-great-skills; scope = any agent-consumed doc; GLOSSARY merged in; SKILL-MECHANICS.md split out; model-invoked (v1.2.2: Codex sidecar policy line REMOVED so it stays model-invocable there); **"cache" pruning term** (environment is SSOT; doc restating it = cache, earns load only when lookup expensive) ≈ our audit-derivability; leading words, negation warning, two loads, information hierarchy |

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
| 30 | `claude-handoff` | PARTIAL | `session-flow:continue-in-background`; handoff `--bg` (#76 cites pocock-v11 slice) | Same idea: handoff → background agent (`claude --bg --name`) |
| 31 | `loop-me` | CONVERGENT | `claude-code-setup:claude-automation-recommender`, `/loop`, `work-items` | Life-loops → workflow specs; push-right checkpoint doctrine; beta — watch |
| 32 | `setup-ts-deep-modules` | NONE | `review:architecture-guardian` (review-time vs his build-time dependency-cruiser enforcement) | TS-specific; beta; interesting completion criterion ("prove the rules bite": pass→fail→pass) |
| 33–35 | `writing-beats` / `writing-fragments` / `writing-shape` | NONE | — | Human-writing workflow (explore/exploit split, beats, grounding); out of our marketplace's scope so far |

## Cross-cutting v1.2 infrastructure (not per-skill)

| Item | His v1.2 | Ours | Assessment |
|---|---|---|---|
| Codex `agents/openai.yaml` sidecars | Every skill; `allow_implicit_invocation: false` mirrors `disable-model-invocation`; v1.2.2 lesson: policy line on a model-invoked skill HIDES it in Codex | None (Claude-only private marketplace) | N/A unless we target Codex; the v1.2.2 lesson is a real gotcha to record if we ever do |
| Claude Code plugin + official marketplace | `claude plugins install mattpocock-skills`; sha-pinned listing; read-only bundle | We ARE a private marketplace already | Parity; his ADR 0002 (Codex plugin deferred: single-path `skills` string + symlink-dropping cache) is good reference material |
| Docs site (aihero.dev/skills) | Per-skill pages, Common questions from real-question wiki, "It's working if" sections, dictionary term links | `docs/` + per-plugin READMEs; no per-skill site | "It's working if" = completion-criteria-for-humans; nice pattern |
| `AGENTS.md` symlink → `CLAUDE.md` | symlink (materializes as plain text on Windows checkouts!) | our CLAUDE.md `@AGENTS.md` import | Ours is Windows-safe; his breaks on Windows — no action |
| Changesets + `sync-plugin-version.mjs` (`--check` drift gate) | package.json ↔ plugin.json version sync enforced | Manual semver per plugin CHANGELOG | Drift-check idea portable to our marketplace lint |
| Buckets: promoted/in-progress(beta)/misc/deprecated(empty—retired=deleted, changeset names replacement) | | Plugins as units; no beta channel | Beta-channel concept interesting; "retired = deleted + changeset names replacement" ≈ our CHANGELOG discipline |
| User-invoked reachability rule | "A user-invoked skill may invoke model-invoked skills, but never another user-invoked skill" | No such stated invariant in our repo | Worth considering as authoring-doctrine line |
| Smart zone ~150k | ask-matt | `context-guard` bands (zone thresholds) | Compare our band figures against 150k claim |
| Upstream issue #693 | Desktop/web surfaces drop user-invoked skills from listing | Affects OUR user-invoked skills too on those surfaces | Recheck trigger candidate |

## Drift/fix findings (our repo, regardless of integration decisions)

> **Lane-1 resolution (2026-08-08):** findings 1, 2, and 4 fixed — provenance moved out of skill
> bodies into `docs/upstream/mattpocock-skills.md` (which carries the observable recheck
> trigger), and the sandcastle research doc now carries a staleness note. Finding 3 resolved as
> "influence, recorded": the SSOT attribution table names both work-items skills. Finding 5 is
> the standing audit baseline (SSOT records v1.2.3 @ `84fdeff`).

1. **STALE**: `plugins/planning/skills/questionnaire/SKILL.md:48-50` says upstream `to-questionnaire` is "in-progress" — it graduated to Productivity in v1.2.0 (#593). Fix provenance line.
2. **WEAK TRIGGER**: "re-audit opportunistically" (questionnaire SKILL.md:50, planning CHANGELOG:562) fails `docs/conventions/upstream-drift/README.md` observability bar — no observable event. The guardrails attribution (`plugins/guardrails/CHANGELOG.md:~1783`) carries NO re-audit trigger at all. Candidate trigger: "a mattpocock/skills release whose changeset names <upstream skill>". [verifier-corrected]
3. **HONESTY FLAG**: `work-items:triage` ("a PR is an item with attached code") and `work-items:decompose` (vertical-slice/tracer-bullet) carry near-verbatim Pocock phrasings with no provenance record. Either coincidence-via-shared-sources or unrecorded influence — decide whether to add provenance lines.
4. **ONE stale reference found** (fresh-context verifier overturned the initial all-clear): `docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md:35,37` (slice carried by PR #330) names `writing-great-skills` as a live upstream skill with no note of the v1.2.0 breaking rename to `writing-for-agents`. Fix or annotate. No other stale references (removed-skill names, `/to-prd`) exist in tracked files. [verifier-corrected]
5. His repo HEAD is v1.2.3, not v1.2.0 — any sync should target HEAD (Redact section, harness-neutral dispatch, wizard sans time-estimates, writing-for-agents Codex-sidecar fix).
