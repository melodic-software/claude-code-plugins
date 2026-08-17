# general-improvement-skill

## Brief

### TLDR

New plugin `improvement` with one skill, `/improvement:find`: an evidence-first, cross-dimension
improvement finder. Point it at any target — a repo, a feature, a concept, a process surface —
with a vague or specific prompt; it produces a ranked, evidence-cited list of improvement
candidates (all sizes, led by highest value-to-effort), deliberates on the picked candidate
through an interview, and hands off to the existing planning pipeline. Routine-runnable
unattended: persists the ranked report and files top candidates as work items, implementing the
autonomy catalog's `tech-debt-sweep` routine contract.

### Goal

Give the fleet its missing "what should we improve here, and how do we know?" entry point:
a finder that forms its own judgment about code/product/process/ops-level improvements,
grounded in evidence, feeding — never bypassing — the existing interview → discovery →
planning → implementation → verification pipeline.

### Constraints

- **Finder-forward hybrid.** The skill's own scan is primary. It delegates to installed
  specialized lanes presence-gated only where they add value (e.g. `architecture:improve`'s
  deepening lens as one input), and never re-implements what an owned lane already does
  (reuse-or-replace posture).
- **Evidence ladder is the core mechanic.** Every candidate cites its evidence (telemetry,
  error/CI failure rates, churn hotspots, or — weakest — model judgment from reading the
  target); ranking confidence is a function of evidence strength; when the target has no
  measurement, the top-ranked candidate becomes "instrument this so future runs can rank on
  data," handed to the pipeline like any other improvement.
- **Evidence sources are tiered and presence-gated.** Tier 0 (always available, ships in V1):
  repo-native signals — git churn/hotspots, CI health via the GitHub MCP, dependency
  staleness, test-coverage presence, TODO density. Tier 1: local Claude Code telemetry via
  `claude-ops:observability` when installed. Tier 2: application telemetry (e.g. Azure App
  Insights, logs) through whatever MCP server the evidence-source config declares — a
  three-layer config cascade in the style of `codebase-health`, never hardcoded Azure. V1
  ships Tier 0 fully plus the gating mechanism.
- **Improvement dimensions** include code/architecture, performance, product-level behavior,
  config/automation outside the codebase (GitHub labeling, Actions, synchronizations), and
  Claude Code operational setup (cloud environments, MCP servers, web sessions).
  Markdown/docs improvement is OUT — owned by existing lanes.
- **Read-only finder; pipeline-mediated execution.** The skill never edits code inline. By
  default it discovers and deliberates only. On an explicit user instruction ("go implement
  this") it proceeds ONLY by chaining the repo's normal skill pipeline — interview →
  `/discovery:explore` / `/discovery:research` → `/planning:plan` →
  `/implementation:implement` → `/verification:confirm` — delegating to those skills.
- **Dual-mode.** Interactive default: present ranked candidates → talk-through interview on
  the pick → pipeline handoff artifact; the rest can be filed as work items. Unattended
  (declared by the caller, e.g. a routine): no questions; persist the ranked report; file top
  candidates via `work-items:track` when installed; never mutates, never self-disposes —
  the `tech-debt-sweep` C1 contract, prioritization human-gated.
- **Unattended noise controls are soft, adaptive, and prompt-tunable — not hard limits.**
  Dedupe against open work items before filing is baseline behavior (filing duplicates is a
  bug, not a tuning knob). Filing volume uses an adaptive cap with a sensible default
  (following `work-items:work-loop`'s adaptive-item-cap precedent), and a
  dismissed-candidate memory is a soft default. Every control is overridable by the
  invocation prompt — the routine prompt wrapping the skill is the tuning surface, and the
  operator iterates on it after observing real runs.
- **Scope: one repo per invocation**, repo as a parameter; routines target repos
  individually; fleet-wide sweeps are a later composition with `repo-fleet-hygiene`.
- **Sizes:** find across small/medium/large; rank by value-to-effort; lead with the
  highest-impact candidate; a prompt or flag narrows the size band.
- **Naming/publishing:** plugin `improvement` (noun, true of every skill under it), skill
  `find` (imperative verb; namespace supplies the object). Full publish gate: plugin.json,
  `./`-prefixed marketplace entry with taxonomy category, `claude plugin validate --strict`,
  regenerate CATALOG + cheat-sheet, `skill-quality:check`, leaf-name registry check,
  explicit "Skip when / NOT for" boundaries against `architecture:improve`,
  `code-tidying:tidy`, `codebase-health:audit`, `review:fanout`, and `work-items:scan-todos`.

### Acceptance criteria

- Bare `/improvement:find` on a repo yields a ranked candidate list; every candidate carries
  an evidence citation, a size (S/M/L), and a value-to-effort rationale; the list leads with
  the highest-impact item.
- A targeted prompt ("improve <feature>", "improve this concept") narrows the scan scope
  accordingly.
- Against a target with no measurement, the top candidate is an instrumentation/baseline
  recommendation, explained as such.
- Interactive mode: picking a candidate enters an interview and ends with a handoff the
  planning pipeline can consume.
- Unattended mode (caller-declared): produces the persisted report, files work items
  presence-gated — deduped against open items, volume governed by the adaptive default
  unless the invocation prompt overrides it — and asks no questions.
- Execution requests route through the pipeline skills; the skill itself performs no code
  edits in any mode.
- Ships past the full publish gate (validate --strict, skill-quality:check, catalog and
  cheat-sheet regenerated) with boundary clauses in the description.

### Captured assumptions

- Marketplace self-improvement (improving this repo's plugins/skills) rides the generic
  dimensions; no special-case marketplace logic in V1.
- The unattended caller-declaration mechanism follows the fleet's existing convention
  (declared by the caller, never sniffed).

### Out of scope (V1)

- Docs/markdown improvement (owned lanes).
- Fleet-wide sweeps (later composition with `repo-fleet-hygiene`).
- Plugin-candidate discovery (deferred, Q10).
- A polished Azure App Insights adapter (deferred, Q12); the Tier 2 gate covers a
  user-configured MCP in the meantime.
- Metrics dashboards/trend visualization; auto-apply/auto-merge of any improvement.

### Deferred questions

- Q10 — arbiter: USER-RESERVED — Plugin-candidate discovery ("what plugin candidates do we
  have, new or existing"): later sibling skill under `improvement` or `plugin-quality`;
  revisit after V1 ships.
- Q12 — arbiter: /planning:plan — Timing of a first-class App Insights/Azure telemetry
  adapter beyond the generic Tier 2 MCP gate.

## Plan

### Goal

**What**: Ship the `improvement` plugin with one skill, `/improvement:find`, per the Brief
above — evidence-first improvement finder, interactive + unattended modes, pipeline-mediated
execution.
**Why**: The fleet has no cross-dimension "what should we improve, and how do we know?" entry
point, and the autonomy catalog's `tech-debt-sweep` routine class has a contract but no
implementation.

### Standards grounding

| Surface | Sections cited | Layer provenance |
|---------|----------------|------------------|
| Plugin placement + naming | `docs/PLUGIN-PHILOSOPHY.md` (noun plugins, imperative-verb skills, verb contracts, one-plugin-per-concern, boundaries-by-design-argument) | team |
| Publish gate | `docs/MIGRATION-PLAYBOOK.md` § per-plugin migration gate (marketplace entry → `claude plugin validate --strict` → regenerate catalog/cheat-sheet) | team |
| Catalog taxonomy | `docs/CATALOG-TAXONOMY.md` (category vocabulary for the marketplace entry) | team |
| Skill schema | `skill-quality:check` gate (frontmatter, listing budget, evals schema, leaf names) + repo check scripts (`check-skill-leaf-names.sh`, `check-skill-portability.sh`, `check-changelog-parity.sh`, `check-plugin-manifest-presence.sh`) | team |
| Config cascade | `docs/conventions/config-cascade/README.md` three-layer shape: `.claude/improvement.md` (team, tracked) + `.claude/improvement.local.md` (gitignored overlay) + `~/.claude/improvement.md` (user-global); `codebase-health` as the in-fleet precedent | team |
| Setup requirement | `docs/PLUGIN-PHILOSOPHY.md` § "Setup is explicit and repeatable" — required here via criterion (a): consumer-project configuration surface | team |

### Phase 1: Plugin scaffold + registration [DONE]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/improvement/.claude-plugin/plugin.json` | Create | `$schema` (claude-code-plugin-manifest), `name: improvement`, `version: 0.1.0`, description, author (Melodic Software), MIT, keywords |
| `plugins/improvement/README.md` | Create | Plugin overview stub (routine guidance lands in Phase 4) |
| `plugins/improvement/CHANGELOG.md` | Create | `0.1.0` entry |
| `.claude-plugin/marketplace.json` | Modify | One entry: `source: ./plugins/improvement`, category from `docs/CATALOG-TAXONOMY.md` controlled vocabulary, tags |

- **Sanity Check:** `claude plugin validate --strict` exits 0 (fallback where the CLI is
  unavailable: `bash scripts/check-plugin-manifest-presence.sh` exits 0 AND
  `check-jsonschema` against the manifest schema exits 0)
- **Sanity Check:** `grep -c '"./plugins/improvement"' .claude-plugin/marketplace.json` returns 1

### Phase 2: Skill body — `/improvement:find` [DONE]

Review: code-design

| File | Action | What changes |
|------|--------|-------------|
| `plugins/improvement/skills/find/SKILL.md` | Create | Full skill contract + workflow |

Required body sections (each is a grep-able heading):

1. **Prompt interpretation** — bare invocation (whole-repo), targeted (`improve <feature/path/concept>`), size-band narrowing (small/medium/large); repo-as-parameter.
2. **Evidence ladder** (the skill's identity) — every candidate cites evidence; confidence =
   f(evidence strength); unmeasured target → instrument-first top candidate.
3. **Evidence sources, tiered + presence-gated** — Tier 0 repo-native (hotspots, CI health,
   dependency staleness, coverage presence, TODO density — recipes in `context/`); Tier 1
   `claude-ops:observability` when installed; Tier 2 configured MCP telemetry via the
   `.claude/improvement.md` cascade. Access-path probe ladder for GitHub data: MCP tools →
   `gh` → none (evidence gap recorded, never fabricated).
4. **Candidate output shape** — ranked list; each row: evidence citation, size S/M/L,
   value-to-effort rationale (WSJF-style); highest-impact leads.
5. **Interactive flow** — present ranked candidates → user picks → interview on the pick →
   pipeline handoff (`/discovery:explore` / `/discovery:research` / `/planning:plan`);
   remainder offered to `work-items:track` presence-gated.
6. **Unattended mode** — caller-declared, never sniffed; no questions; report persisted to the
   topic memory slice; top candidates filed via `work-items:track` presence-gated with
   dedupe-against-open-items (baseline behavior), adaptive filing cap and dismissed-candidate
   memory as soft, prompt-overridable defaults (tech-debt-sweep C1 alignment: read-only,
   never self-disposes).
7. **Execution requests** — "go implement this" routes through interview → discovery →
   plan → implement → verify via existing skills; the skill never edits code in any mode.
8. **Scan dimensions** — the explicit inventory the scan walks so it cannot silently collapse
   to code-only: code/architecture, performance, product-level behavior, config/automation
   outside the codebase (GitHub labels/Actions/synchronizations), Claude Code operational
   setup (cloud envs, MCP servers); docs/markdown explicitly OUT (owned lanes).
9. **Lane delegation as scan input** — presence-gated consultation of installed specialized
   finders (e.g. `architecture:improve`'s deepening lens, `claude-config:audit-automation-gaps`
   for the ops dimension) as inputs to the candidate list — delegate, never re-inline.
10. **What this skill does NOT do / Skip when** — boundaries vs `architecture:improve`
    (single-lens architecture depth), `code-tidying:tidy` (applies small safe edits),
    `codebase-health:audit` (drift/claim verification), `review:fanout` (diff-scoped),
    `work-items:scan-todos` (marker sweep); reuse-or-replace posture. Includes the verb-contract
    note: `find` reads as read-only, and it is — the caller's unattended declaration IS the
    explicit mutation override that authorizes work-item filing (mirroring the `audit`-verb
    override shape); no other mutation exists in any mode.

- **Sanity Check:** `CHECK_SKILL_SKILLS_ROOT=plugins/improvement/skills bash plugins/skill-quality/scripts/check-skill.sh find` exits 0
- **Sanity Check:** frontmatter description contains `Skip when` AND names at least
  `architecture:improve` and `code-tidying:tidy`;
  `grep -Ec "Evidence ladder|Scan dimensions|Unattended|Skip when" plugins/improvement/skills/find/SKILL.md` ≥ 4
- **Sanity Check:** no `name:` key in frontmatter (defaults to directory name):
  `grep -c '^name:' plugins/improvement/skills/find/SKILL.md` returns 0

### Phase 3: Evidence recipes (`context/` leaves) [DONE]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/improvement/skills/find/context/hotspots.md` | Create | Plain-git churn×complexity recipe: `git log --since` windowed change-frequency, indentation-count complexity proxy (LOC recorded alongside), churn×complexity quadrant ranking, bundled default exclusion globs (lockfiles/generated/vendored) overridable via the config cascade. **History-depth gate first**: `git rev-parse --is-shallow-repository` + window-coverage check (oldest commit vs requested `--since` window); shallow/truncated history downgrades churn to a recorded evidence gap (or instrument-first candidate) — never confidently-wrong rankings from partial history |
| `plugins/improvement/skills/find/context/ci-health.md` | Create | `GET /repos/{o}/{r}/actions/runs` with `created` date-window iteration (never deep pagination), `conclusion` failure ratios, `updated_at − run_started_at` duration trend, `run_attempt` retry detection; explicit "never `/timing` (deprecating)"; MCP `actions_*` / `gh` / none probe ladder; **zero-runs / no-Actions branch** resolves to an evidence gap or instrument-first candidate, never an error; portability-scope declaration (GitHub-forge-specific recipe under a neutral dimension — non-GitHub forges = recorded gap) |
| `plugins/improvement/skills/find/context/ranking.md` | Create | WSJF-style value-to-effort scoring; evidence-strength → confidence mapping; instrument-first rule (SRE error-budget precedent); dedupe + dismissed-memory consultation order |
| `plugins/improvement/skills/find/context/unattended.md` | Create | Caller-declaration contract, report shape, filing flow (search-before-create per tracker convention), adaptive cap default, routine-prompt override points; **report home** = `${CLAUDE_PLUGIN_DATA}` per the plugin-data-report-keying convention (consumer-repo-agnostic; never assumes this repo's topic-docs layout), with the dismissed-candidate memory keyed alongside |

- **Sanity Check:** `grep -l "run_attempt" plugins/improvement/skills/find/context/ci-health.md`
  AND `grep -l "indentation" plugins/improvement/skills/find/context/hotspots.md`
  AND `grep -l "instrument" plugins/improvement/skills/find/context/ranking.md` all non-empty
- **Sanity Check:** `grep -c "timing" plugins/improvement/skills/find/context/ci-health.md` ≥ 1
  (the deprecation warning is present)
- **Sanity Check:** `grep -Ec "shallow|is-shallow-repository" plugins/improvement/skills/find/context/hotspots.md` ≥ 1
- **Sanity Check:** `npx markdownlint-cli2 "plugins/improvement/**/*.md"` exits 0

### Phase 4: Setup skill, config contract, evals, README routine guidance [DONE]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/improvement/skills/setup/SKILL.md` | Create | Fleet-standard setup skill: `disable-model-invocation: true`, actions `check` (default) / `apply` only; verifies/creates the `.claude/improvement.md` cascade files and reports the effective evidence-source configuration. Required by PLUGIN-PHILOSOPHY criterion (a) — consumer-project configuration surface |
| `plugins/improvement/reference/config.md` | Create | The config-key contract (single home): evidence-source declarations (Tier 2 MCP sources), churn exclusion globs, cascade resolution order across all three layers |
| `plugins/improvement/skills/setup/evals/evals.json` | Create | Minimal setup evals per fleet pattern |
| `plugins/improvement/skills/find/evals/evals.json` (+ `fixtures/`) | Create | Minimal eval set per skill-quality schema: trigger-recognition cases (vague prompt, targeted prompt, unattended declaration) |
| `plugins/improvement/README.md` | Modify | Routine-wrapper section: recommended Routine prompt template (weekly cadence; prompt = tuning surface for cap/scope/dismissals) **including the fired-environment prerequisite** (the plugin must be installed in the fired session's environment per `docs/CLOUD-SESSIONS.md`; template prompt opens with "if `/improvement:find` is unavailable, stop and report") — plus GitHub Actions cron alternative (`claude-code-action@v1` + `plugins:` input), `/loop` noted as session-scoped only |
| `plugins/improvement/CHANGELOG.md` | Modify | Finalize 0.1.0 notes |

- **Sanity Check:** `CHECK_SKILL_SKILLS_ROOT=plugins/improvement/skills bash plugins/skill-quality/scripts/check-skill.sh setup` exits 0
- **Sanity Check:** `grep -c "disable-model-invocation: true" plugins/improvement/skills/setup/SKILL.md` returns 1
- **Sanity Check:** `grep -Ec "improvement.local.md|improvement.md" plugins/improvement/reference/config.md` ≥ 2 (all cascade layers documented)
- **Sanity Check:** `grep -Ec "Routine|cron" plugins/improvement/README.md` ≥ 2 AND `grep -c "unavailable" plugins/improvement/README.md` ≥ 1

### Phase 5: Trigger-boundary handshake with `architecture:improve` [DONE]

`architecture:improve`'s description currently claims "what should we improve" and "find
refactoring opportunities" — the new skill's core triggers. One-sided boundaries don't resolve
an auto-invocation race; this phase implements the "both ways" mitigation.

| File | Action | What changes |
|------|--------|-------------|
| `plugins/architecture/skills/improve/SKILL.md` | Modify | Description only: add a negative-routing clause handing cross-dimension / evidence-driven / "highest-impact improvement" asks to `/improvement:find`; keep architecture-lens triggers |
| `plugins/architecture/.claude-plugin/plugin.json` | Modify | Version bump (patch) |
| `plugins/architecture/CHANGELOG.md` | Modify | Entry for the boundary clause |

- **Sanity Check:** `grep -c "improvement:find" plugins/architecture/skills/improve/SKILL.md` ≥ 1
- **Sanity Check:** trigger-continuity check passes: `CHECK_SKILL_BASE_REF=origin/main CHECK_SKILL_SKILLS_ROOT=plugins/architecture/skills bash plugins/skill-quality/scripts/check-skill.sh improve` exits 0
- **Sanity Check:** `bash scripts/check-changelog-parity.sh` exits 0 (architecture version/CHANGELOG in step)

### Phase 6: Fleet gates, catalog regeneration, smokes [DONE]

Steps (scriptable gate run — commands already exist in-repo):

1. `bash scripts/check-skill-leaf-names.sh --check` (no unregistered collision — `find` leaf
   is currently unclaimed fleet-wide)
2. `bash scripts/check-skill-portability.sh` AND `bash scripts/check-shell-portability.sh`
   (the Phase 3 recipes carry live git/awk blocks — GNU-only constructs are the trap)
3. `bash scripts/check-changelog-parity.sh`
4. `claude plugin validate --strict "$(git rev-parse --show-toplevel)"` — repo root, so the
   catalog manifest itself is validated (fallback where the CLI is unavailable per Phase 1)
5. `node scripts/generate-catalog.mjs` and `node scripts/generate-cheatsheet.mjs` — commit the
   regenerated `docs/CATALOG.md` / `docs/SKILL-CHEAT-SHEET.md`
6. Dogfood smoke: dispatch a fresh subagent invoking `/improvement:find` against this repo;
   save its output to the topic memory slice
7. Clean-repo smoke (playbook gate step 9 — proves repo-agnosticism): load the plugin with
   `claude --plugin-dir ./plugins/improvement` in a repo that is NOT this one (a scratch clone
   without the fleet, CI history, or topic-docs layout); verify the skill produces a ranked
   report with honestly-recorded evidence gaps instead of erroring or fabricating

- **Sanity Check:** every gate command above exits 0
- **Sanity Check:** `git diff --name-only` after regeneration includes `docs/CATALOG.md`
- **Sanity Check:** the saved dogfood output contains ≥1 candidate with a non-empty evidence
  citation and an S/M/L size marker (grep the saved file for the size field and an
  `evidence` field)
- **Sanity Check:** the saved clean-repo output contains ≥1 recorded evidence-gap line
  (grep for `gap`) and zero fabricated CI/telemetry claims

### Test Strategy

No executable code ships — the deliverable is prose contracts + JSON manifests. TDD
(Red-Green-Refactor) is genuinely impractical here; verification is: (a) the deterministic
fleet gates (schema validation, leaf-name/portability/shell-portability/changelog checks,
markdownlint, typos — all repo-standard), (b) eval fixtures for trigger recognition, (c) the
Phase 6 dogfood + clean-repo smokes as end-to-end runtime probes. Regression surface for
existing components: one description-only edit to `architecture:improve` (Phase 5), guarded
by the trigger-continuity check; everything else is additive.

### Alternatives Considered

| Alternative | Why rejected |
|-------------|-------------|
| Add a lens to `architecture:improve` instead of a new plugin | Its lens system extends architecture scanning only; the Brief's scope (product, process, ops, telemetry dimensions + unattended routine mode) exceeds the lens contract |
| Two skills (`find` + `sweep`) for interactive vs unattended | One discovery intent; fleet rule says split on discovery intent, not mode — mode is caller-declared |
| Bundle evidence recipes into SKILL.md body | Blows the listing/context budget; fleet convention is progressive disclosure via `context/` leaves |
| Hard-coded noise caps in the unattended contract | Interview Q11 decided adaptive, prompt-tunable soft defaults |

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Skill description overlaps trigger-wise with `architecture:improve` ("what should we improve") | Med | Med | Boundaries implemented BOTH ways: Phase 2 §10 Skip-when clause + Phase 5 edits `architecture:improve`'s description with a negative-routing handover (trigger-continuity-checked); Phase 6 leaf-name check |
| Shallow/truncated clone yields confidently wrong churn rankings | Med | Med | Phase 3 history-depth gate: shallow or window-uncovered history downgrades churn to a recorded evidence gap |
| `claude plugin validate` CLI unavailable in some environments | Med | Low | Documented fallback gate (manifest-presence + jsonschema checks) in Phase 1 |
| Unattended run without GitHub access path silently degrades | Low | Med | Probe ladder records an explicit evidence-gap line in the report — absence is reported, never faked |
| Routines surface is research-preview (caps may drift) | Med | Low | README routine guidance cites the docs page rather than pinning caps; re-verify at implementation per research note |
| Evals schema drift vs skill-quality expectations | Low | Low | Phase 5 gate run catches; evals kept minimal |

## Blast radius

**LOW.** One new plugin directory (additive); existing files modified: `.claude-plugin/marketplace.json`
(one appended entry), the two regenerated catalog docs, and a description-only edit to
`plugins/architecture/skills/improve/SKILL.md` (+ its version/CHANGELOG) for the trigger
handover — guarded by the trigger-continuity check and reversible in one commit. No behavior,
hook, or contract changes to any existing component. No stress-test triggers matched
(no shared-state mutation, no destructive operations, no cross-cutting refactor, no security
surface).

## Stress-test summary

Step 3 fresh-context plan review: 11 findings (1 CRITICAL, 5 IMPORTANT, 5 SUGGESTION), all
verified against the repo and folded in — the CRITICAL (missing `setup` skill for the config
surface, required by PLUGIN-PHILOSOPHY criterion (a)) became Phase 4's setup deliverables; the
IMPORTANT findings became the Phase 5 boundary handshake, the clean-repo smoke + repo-root validate,
the Scan-dimensions/Lane-delegation sections, the corrected `check-skill.sh` invocations, and
the shallow-history gate. Formal `/planning:devils-advocate` (Step 4): **Skipped — blast
radius LOW, no triggers matched.**

## Execution shape

Phases 1 → 2 → (3 ∥ 4 ∥ 5) → 6. Phases 3, 4, and 5 are pairwise file-disjoint (context/
leaves vs setup+evals+README vs the architecture plugin) and depend only on Phase 2;
parallelizing saves modest prose LOC — **recommended shape: fully sequential in one
implementer session** (simplest; total scope ~8–12 files of prose); the parallel option
exists with the standard scope-fence (each phase touches only its listed files; PLAN.md stays
orchestrator-owned).

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent implementer (or main) | mechanical scaffold from template |
| 2 | sub-agent implementer | judgment-heavy authoring, but fully specified by Brief + this plan |
| 3 | sub-agent implementer | recipe transcription from verified research |
| 4 | sub-agent implementer | mechanical (setup skill follows fleet template) |
| 5 | sub-agent implementer | one description edit + version/CHANGELOG, tightly specified |
| 6 | main session | gate run + commit + smoke verdicts need orchestrator judgment |

## Open questions

None blocking. Brief-level deferrals stand: Q10 (plugin-candidate discovery, USER-RESERVED),
Q12 (App Insights adapter timing, planning-time → resolved as post-V1; the Tier 2 MCP gate
covers a user-configured source in the meantime).

## Handoff to implementation

### User-approval gates

- None beyond plan approval — no `[FALLBACK]` tags; no scope expansion anticipated. A
  mid-implementation pivot that changes the Brief's acceptance criteria returns to
  `/planning:plan review`.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| `[EXEC-SHAPE]` Complexity proxy = indentation count (LOC recorded alongside) | Phase 3 hotspots recipe | CodeScene enterprise docs (fetched, verifier-confirmed): indentation is the canonical mechanical metric of the hotspot method |
| `[EXEC-SHAPE]` Churn exclusions = bundled default globs, overridable via `.claude/improvement.md` cascade | Phase 3 recipe + config surface | `codebase-health` cascade pattern read this session; research falsification pass flagged lockfile/generated-churn noise |
| `[EXEC-SHAPE]` GitHub access = probe ladder MCP → `gh` → none, with recorded evidence gaps | Phase 2 §3 + Phase 3 ci-health recipe | This session observed cloud env without `gh`; fleet portability convention; research confirmed MCP `actions_*` parity |
| `[EXEC-SHAPE]` V1 operator docs recommend Routines (primary) + GH Actions cron (alternative) | Phase 4 README section | Research: Routines' fresh-session + prompt-as-tuning-surface matches the Brief's Q11 noise-control decision and the tech-debt-sweep temporal contract |
| `[EXEC-SHAPE]` Recipes as `context/` leaves, not SKILL.md body | Phase 2/3 file layout | Fleet progressive-disclosure convention (`architecture:improve` shape); listing budget |
| `[EXEC-SHAPE]` Single skill, dual mode (no `sweep` sibling) | Whole plan | Fleet rule: skills split on discovery intent, not mode; Brief Q3 |
| `[EXEC-SHAPE]` Ship a `setup` skill + `reference/config.md` config contract | Phase 4 | PLUGIN-PHILOSOPHY § setup criterion (a) verified this session; `codebase-health` precedent; plan-review CRITICAL finding |
| `[EXEC-SHAPE]` Edit `architecture:improve`'s description for a two-way trigger handover | Phase 5 | Its description verifiably claims "what should we improve" / "find refactoring opportunities"; one-sided boundaries can't resolve an auto-invocation race; guarded by trigger-continuity check |
| `[EXEC-SHAPE]` Unattended report + dismissed-memory home = `${CLAUDE_PLUGIN_DATA}` | Phase 3 unattended recipe | Consumer-repo-agnostic per the plugin-data convention; a consumer repo has no topic-docs layout to assume |

### Execution shape ([EXEC-SHAPE] tagged)

Sequential single-implementer execution per the routing table above; scope fence per phase =
that phase's file table; PLAN.md status tags advanced by the orchestrator only.

### Mechanical work

- Commit boundary per phase (conventional commits: `feat(improvement): …`); push after each.
- Verification checkpoint = each phase's Sanity Check block before its commit.
- Sequential fallback n/a (sequential is the recommended shape).
- Branch: stays on `claude/general-improvement-skill-c9e8zc` (designated by session
  constraints — overrides the conventional-prefix rename suggestion).
