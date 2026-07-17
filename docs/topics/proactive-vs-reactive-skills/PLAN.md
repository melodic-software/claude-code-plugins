# proactive-vs-reactive-skills

## Brief

### TLDR

Development-workflow skills load the consumer's standards proactively (at plan/build time) instead of colliding with them reactively at review time. One shared, concern-named standards index — consumed by planning AND review — makes skills build to the criteria they'll be reviewed against.

### Goal

Eliminate the rework loop where `/architect`-planned and `/implement`-built work violates consumer standards (code conventions, engineering philosophy, design-review criteria) that only surface during review. Proactive grounding becomes the DEFAULT behavior of lifecycle skills — no mode fork, no sibling skill variants — with cost governed by existing scale/blast-radius gates and progressive disclosure.

V1 (locked): the `standards` concern contract + a two-consumer pilot.

1. Versioned concern contract at `docs/conventions/standards/` — index schema, layers, precedence, resolution ladder.
2. `planning:architect` gains a proactive standards-loading step (plan formulation grounds in the loaded criteria).
3. `review:quality-gate` `criteria` mode resolves criteria through the SAME index (build/review symmetry).
4. Idempotent setup bootstrap in those two plugins only.

Fleet rollout (implement, design, prototype, testing, …) follows in per-plugin waves after the pilot proves the contract.

### Constraints

- **Repo-agnostic, no baked opinions (C1).** Every default — including the concern folder location — is reconfigurable via re-runnable setup. Only the discovery anchor stays conventional. Plugin never names the user's org, repos, or layout.
- **Default layout (three layers, seam-2 shape):** user-global `~/.claude/standards/` → team-tracked `docs/standards/` → personal gitignored `docs/standards/*.local.md` (setup ships the `.gitignore` line). Team layer deliberately OUTSIDE `.claude/` (verified: `.claude/` writes are specially permission-guarded even under acceptEdits; reads are prompt-free anywhere in the working directory).
- **Policy precedence inversion:** layers are additive; personal layers may ADD or TIGHTEN only; direct conflict → team-tracked wins. Skills state which layer contributed when a personal rule materially shapes output.
- **Progressive disclosure:** root index is a thin routing map (in-scope surfaces + context clues, no content); standards files are SRP-organized (one concern per file); skills pull only sections matching the surfaces the task touches (e.g. C# conventions only when touching C#).
- **Resolution ladder (playbook-adopted):** index present → use it; absent → infer from not-auto-loaded usual suspects (docs folders, ecosystem configs — never re-read auto-loaded CLAUDE.md/.claude/rules) and OFFER to persist; can't infer → ask once; else safe ecosystem default. No silent writes, ever.
- **Setup mode 2:** skills usable immediately with defaults; setup optional, idempotent, re-runnable anytime; setup may offer (never force) reorganizing mixed/spread consumer standards content toward the SRP + index shape.
- **Horizontal decoupling:** no cross-plugin imports. Each consuming plugin carries a synced `reference/` binding copy of the contract (topic-docs/hook-utils precedent); per-plugin idempotent bootstrap — first setup writes the index, later setups validate/offer reconfigure.
- **Anti-waterfall:** grounding depth rides the existing plan-scale/blast-radius gates; trivial work pays near zero. No grounding flag, no `--ungrounded` escape hatch.
- **Process gates:** fresh-docs mandate (WebFetch current plugin docs) before any file change; per-plugin migration gate + plugin-acceptance security review; version bumps + changelog per delivery rules.

### Acceptance criteria

- `docs/conventions/standards/README.md` exists: index schema, three layers, precedence-inversion rule, resolution ladder, versioning — and both pilot plugins carry a synced binding copy.
- `plugins/planning/skills/architect/SKILL.md` carries the proactive standards step; a plan produced for a task touching surface X cites the standards sections loaded for X; grounding depth demonstrably scales with the plan-scale tier (trivial plan → no standards fetch beyond ambient context).
- `plugins/review/skills/quality-gate` `criteria` mode resolves criteria through the same index when present (grep confirms the binding reference, exercise confirms the load).
- Setup in both pilot plugins bootstraps `docs/standards/` idempotently in a clean non-source repo via `--plugin-dir` (run twice → no diff on second run).
- Absent-index fallback: in a repo with no index, the skill infers from repo context and offers persistence — verified by exercise; zero unprompted writes.
- No hardcoded consumer paths (`grep` for absolute paths / org names in changed plugin files → zero hits); `claude plugin validate` passes; both plugins version-bumped with changelog entries.

### Captured assumptions

- File reads need no permission approval anywhere in the working directory, all environments; `.claude/` writes sit on the protected-directory prompt list (both verified against the official permissions doc, 2026-07-17).
- `standards` is the umbrella term (adopted conventions become standards — research-confirmed 2026-07-17); "guidance" rejected as advisory-only connotation.
- Auto-loaded surfaces (consumer `CLAUDE.md`, `.claude/rules`) apply ambiently and are never re-fetched by the grounding step.
- Two consumers (one proactive, one reactive) are sufficient to validate the multi-plugin concern design before fleet rollout.

### Out-of-scope

- Dual proactive/reactive skill variants and mode flags — ruled out (playbook: depth/intensity variants are arguments, never siblings; here not even an argument).
- Meta-setup plugin for shared plugin conventions — deferred; trigger: ≥3 shared concerns AND observed bootstrap drift/nagging across plugins.
- Restructuring the `melodic-software/standards` repo itself ("am I doing the standards repo right") — separate effort, own session.
- Fleet rollout waves beyond the two-plugin pilot — planned after pilot verdict.

### Deferred questions

- Index/contract schema detail (surface taxonomy: ecosystem × layer × stage; file format; root-index shape) → **/design**
- Per-skill step placement inside architect/quality-gate bodies + binding-copy sync mechanics (extend existing sync machinery?) → **/architect**
- Plugin-upgrade migration handling: inside re-runnable setup vs separate action → **/design**
- Wave-2 rollout inventory + inclusion rule (which dev-workflow skills, what order) → **USER-RESERVED** (scope decision at wave time)

## Plan

Fresh-docs verified this session (2026-07-17): skills frontmatter fields incl. `disable-model-invocation` / `user-invocable` / `argument-hint` (<https://code.claude.com/docs/en/skills>); `claude plugin validate <dir> --strict`, `--plugin-dir` session loading, `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`, and `pluginConfigs` user-settings-only storage (<https://code.claude.com/docs/en/plugins-reference>). Implementation phases MUST re-fetch the pages relevant to the files they touch (repo fresh-docs mandate) before editing.

**Build technique:** committed work, integration risk → tracer bullet. The integration spine (contract + sync machinery, Phases 1–2) lands first and is verified end-to-end (canonical → synced copies → CI drift gate) before either consumer skill is rewired.

### Phase 1: Contract home — `docs/conventions/standards/` [TODO]

Materialize `contract-spec.md` as the canonical convention, following the marketplace convention template (`docs/conventions/topic-docs/` precedent: README + CHANGELOG + schema + examples).

| File | Action | What changes |
|------|--------|-------------|
| `docs/conventions/standards/README.md` | Create | The contract: YAML frontmatter `standards-contract: 1.0.0` (self-describing version — see D2); index schema + columns; external-row validation duty; standards-file rules (SRP, pure prose); personal overlays; user-global layer; `.claude/standards.yaml` concern file + resolution ladder; `.claude/rules` division-of-content seam + pointer pattern; versioning; **normative "Setup and migration" section** (bootstrap procedure, idempotency, run-twice-no-diff, version-delta detection + guided migration, tolerant-reader rule) — single home for the procedure both plugins implement by reference. **Stress-test additions (DA):** presence test is normative — an index exists iff the `standards-contract` frontmatter key is present; a `<standards_dir>/README.md` without it is pre-existing content = inference source only, and setup treats it as hand-authored, requiring explicit confirmation before any conversion (DA-F5). Resolution root = git top-level (concern file discovered there); index `File` paths are forward-slash repo-relative (DA-F6). Version-delta detection is DIRECTIONAL: index newer than the reading plugin's bundled contract → best-effort read, NEVER offer migration (no downgrades), message "update the <plugin> plugin" (DA-F3). Setup short-circuits without interview when a conforming index at the bundled version exists (DA-F11). Size guidance: SRP + soft per-file budget, recommend splitting oversized files; grounding reads matched files selectively — sections relevant to the task, not necessarily whole files (DA-F8). The **"Resolution ladder" is a clearly-delimited section** skills jump to (progressive disclosure within the binding); consuming SKILL.md files carry pointer language only, never a restated ladder (DA-F9). Authoring constraint: no relative markdown links in the README — the synced copies would 404 in the offline lychee lane; backtick file names instead (DA-F12) |
| `docs/conventions/standards/standards.schema.json` | Create | JSON Schema for `.claude/standards.yaml` (`standards_dir` string, all keys optional) — `topic-docs.schema.json` / `ecosystem.schema.json` precedent |
| `docs/conventions/standards/CHANGELOG.md` | Create | `1.0.0` initial entry |
| `docs/conventions/standards/examples/worked-index.md` | Create | One worked consumer index (in-root rows, one external row, one `.local.md` overlay note) |

Content authority: `docs/topics/proactive-vs-reactive-skills/design/contract-spec.md` + Brief constraints. Additive contract text beyond the spec is limited to D2 (version frontmatter) plus the enumerated DA additions above — each closes a stress-test gap without contradicting a RESOLVED design thread.

**Sanity Check:**

- `grep -c "standards-contract: 1.0.0" docs/conventions/standards/README.md` returns ≥1 (frontmatter); `grep -c "^## 1.0.0" docs/conventions/standards/CHANGELOG.md` ≥ 1
- `jq -e . docs/conventions/standards/standards.schema.json` exit 0
- `grep -cE "^## " docs/conventions/standards/README.md` ≥ 6 (index schema, files, overlays, user-global, concern file, rules seam, versioning/setup present)
- markdownlint + repo link-check lanes pass on the new files

### Phase 2: Sync machinery + binding copies [TODO]

Byte-identical binding copies delivered by a dedicated sync script (hook-utils shape — see D1), registered as a cross-plugin cluster.

**Pre-flight (first item):** `ls plugins/*/reference/` and `grep -rn "standards-contract" plugins/ scripts/ .github/` — confirm no existing `standards-contract.md` collision and no consumer already parsing that name. Verified this session: none exist; review plugin has no `skills/setup/`.

| File | Action | What changes |
|------|--------|-------------|
| `scripts/sync-standards-contract.sh` | Create | Mirrors `sync-hook-utils.sh` shape: `sync` (copy `docs/conventions/standards/README.md` into every plugin carrying `reference/standards-contract.md`), `--check` (byte-compare), `--check-bump <ref>` (contract changed but a carrying plugin's manifest version didn't → fail). **Beyond the hook-utils shape (DA-F4):** `--check-bump` additionally fails when canonical content changed vs base but the `standards-contract` frontmatter semver did NOT change or `CHANGELOG.md` gained no new `##` heading — the frontmatter version is what T6 migration detection reads; without this, content drifts under a frozen version forever. Opt-in by file presence — fleet waves add plugins without script edits |
| `scripts/sync-standards-contract.test.sh` | Create | **Written first (Red)** — test-first per TDD default; asserts sync/`--check`/`--check-bump` behavior incl. the frontmatter-bump + changelog-heading failure cases, against temp fixtures (`check-cross-plugin-source-drift.test.sh` precedent) |
| `plugins/planning/reference/standards-contract.md` | Create | Initial opt-in copy (byte-identical to canonical) |
| `plugins/review/reference/standards-contract.md` | Create | Initial opt-in copy |
| `scripts/cross-plugin-source-registry.txt` | Modify | Register `reference/standards-contract.md` cluster, comment naming the dedicated check (required — an unregistered identical cluster fails `check-cross-plugin-source-drift.sh --check`) |
| `.github/workflows/ci.yml` | Modify | New `standards-contract-sync` job mirroring `hook-utils-sync` (`--check`, test run, `--check-bump origin/$BASE_REF`); add to the final aggregate gate's `needs` list |

**Sanity Check:**

- `scripts/sync-standards-contract.sh --check` exit 0; `bash scripts/sync-standards-contract.test.sh` exit 0
- `cmp docs/conventions/standards/README.md plugins/planning/reference/standards-contract.md` exit 0 (same for review copy)
- `scripts/check-cross-plugin-source-drift.sh --check` exit 0 (cluster registered)
- `grep -c "standards-contract-sync" .github/workflows/ci.yml` ≥ 2 (job + needs entry)

### Phase 3: planning plugin — proactive grounding + setup extension [TODO]

Review: code-design

Fresh-docs re-fetch (skills page) before edits.

| File | Action | What changes |
|------|--------|-------------|
| `plugins/planning/skills/architect/SKILL.md` | Modify | New **"Ground in consumer standards"** subsection at the TOP of Step 2 (formulation input, not a Step 1 gate — anti-waterfall; see D3): resolve the index per the contract ladder via the binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`]; match task surfaces against `Applies when` clues; pull ONLY matched files not already ambient (fired rules / CLAUDE.md never re-pulled; post-compaction context counts as NOT-ambient — re-resolve per task, so a second task in the same session grounds its own surfaces); depth rides the existing Step 2 plan-scale table (trivial → no fetch beyond ambient); personal-layer provenance named when a `.local.md` rule shapes the plan; broken external row → surface + offer fix (Boy Scout, never silent); older-index → best-effort + "index at vX, contract at vY — re-run setup"; absent index → infer from not-auto-loaded usual suspects, OFFER to persist, ask once, else safe default — zero unprompted writes. Reads matched files SELECTIVELY (task-relevant sections, DA-F8); the ladder itself is NOT restated in SKILL.md — pointer to the binding's delimited "Resolution ladder" section only (DA-F9) |
| `plugins/planning/tests/standards-binding.test.sh` (location per repo `plugins/**/*.test.sh` precedent) | Create | **Tripwire contract test (DA-F7):** greps assert the load-bearing markers survive future prose edits — grounding heading inside Step 2, binding reference in architect + setup SKILL.md, no restated-ladder keywords. Picked up automatically by `scripts/run-plugin-tests.sh` |
| `plugins/planning/skills/architect/context/plan-template.md` | Modify | Full template gains a **"Standards grounding"** element (table: surface → sections cited → layer provenance); scale guidance notes trivial/small skip |
| `plugins/planning/skills/architect/context/plan-reviewer.md` | Modify | Reviewer axis: "plan cites the standards sections loaded for the surfaces it touches, or states why grounding was skipped (scale tier)" |
| `plugins/planning/skills/setup/SKILL.md` | Modify | Second concern: standards bootstrap per the binding's normative Setup-and-migration section — read state (`.claude/standards.yaml` → index → inference), interview, bootstrap `docs/standards/README.md` skeleton + overlay ignore line, validate every index row path, version-delta detection + guided migration, optional pointer-rule generation (interactive only). Frontmatter `description` updated to cover both concerns. **Explicit reconciliation work item (reviewer F1):** the skill currently prohibits editing ignore files twice (Task step 4; What-this-skill-does-NOT-do). The overlay line ships as a setup-created `<standards_dir>/.gitignore` containing `*.local.md` — never a consumer root-`.gitignore` edit — and both prohibition passages are amended to scope: setup never edits an ignore file it did not create; the standards root's own bootstrap-shipped `.gitignore` is setup-owned. Contract README (Phase 1) words the mechanism identically |
| `plugins/planning/skills/architect/evals/evals.json` | Modify | Case: task touching surface X in an index-present fixture → plan cites X's sections |
| `plugins/planning/skills/setup/evals/evals.json` | Modify | Case: standards bootstrap idempotency (second run proposes no changes) |
| `plugins/planning/.claude-plugin/plugin.json` | Modify | `0.12.0` → `0.13.0` |
| `plugins/planning/CHANGELOG.md` | Modify | `0.13.0` entry |

**Sanity Check:**

- `grep -c "standards-contract.md" plugins/planning/skills/architect/SKILL.md` ≥ 1 and same grep ≥ 1 in `plugins/planning/skills/setup/SKILL.md`
- `grep -c "Ground in consumer standards" plugins/planning/skills/architect/SKILL.md` = 1, located inside Step 2 (Read assertion)
- `grep -c "Standards grounding" plugins/planning/skills/architect/context/plan-template.md` ≥ 1
- `jq -r .version plugins/planning/.claude-plugin/plugin.json` = `0.13.0`; CHANGELOG head entry matches
- `grep -rniE "melodic-software|kyle" plugins/planning/skills/architect/SKILL.md plugins/planning/skills/setup/SKILL.md` returns 0 hits (repo-agnostic)

### Phase 4: review plugin — criteria rewire + new setup skill [TODO]

Review: code-design

Fresh-docs re-fetch (skills page) before edits.

| File | Action | What changes |
|------|--------|-------------|
| `plugins/review/skills/quality-gate/context/criteria.md` | Modify | "How to use" step 1 rewired: resolve criteria through the standards index per the contract ladder via the binding (`.claude/standards.yaml` → `docs/standards/README.md` → declared/inferred location with offer-to-persist → ask once); existing REVIEW.md / docs-directory discovery becomes an inference source inside the ladder, not the primary; baseline (`severity.md` + agent checklists) stays the final fallback; tolerant-reader + broken-row Boy Scout lines added |
| `plugins/review/skills/quality-gate/SKILL.md` | Modify | One line in Shared inputs: criteria resolution goes through the plugin binding `reference/standards-contract.md`. **DA-F1 resolution (user-approved 2026-07-17):** Step 1 item 3 ("What conventions apply?") rewired through the same index resolution — one sentence, so ALL review modes (self/code/security/pr) inherit index-grounded conventions, not just criteria mode |
| `plugins/review/skills/setup/SKILL.md` | Create | New skill, `planning:setup` frontmatter shape (`user-invocable: true`, `disable-model-invocation: true`): standards bootstrap implementing the binding's normative Setup-and-migration section (same semantics as planning's — single home in the contract, no duplicated procedure prose) |
| `plugins/review/skills/setup/evals/evals.json` | Create | Bootstrap + idempotency cases |
| `plugins/review/skills/quality-gate/evals/evals.json` | Modify | Case: criteria mode in index-present fixture resolves through the index |
| `plugins/review/tests/standards-binding.test.sh` (location per repo `plugins/**/*.test.sh` precedent) | Create | **Tripwire contract test (DA-F7):** greps assert criteria.md's binding reference + ladder pointer and the setup skill's binding reference survive future prose edits |
| `plugins/review/.claude-plugin/plugin.json` | Modify | `0.9.0` → `0.10.0` |
| `plugins/review/CHANGELOG.md` | Modify | `0.10.0` entry |

**Sanity Check:**

- `grep -c "standards-contract.md" plugins/review/skills/quality-gate/context/criteria.md` ≥ 1; `test -f plugins/review/skills/setup/SKILL.md`
- `grep -c "disable-model-invocation: true" plugins/review/skills/setup/SKILL.md` = 1
- `jq -r .version plugins/review/.claude-plugin/plugin.json` = `0.10.0`; CHANGELOG head entry matches
- `grep -rniE "melodic-software|kyle" plugins/review/skills/` returns 0 hits in changed files

### Phase 5: Verification, exercise, and gates [TODO]

Review: security

Runbook results distill into this PLAN's verification notes; raw transcripts stay in `.work/proactive-vs-reactive-skills/`.

1. **Mechanical:** `claude plugin validate plugins/planning --strict` and `claude plugin validate plugins/review --strict` exit 0; full CI lanes green (incl. new `standards-contract-sync`, `cross-plugin-source-drift`, link-check).
2. **Fixture exercises** (acceptance-criteria seam, T7): clean temp non-source repos via `claude --plugin-dir` —
   - *index-present:* task touching surface X → plan cites X's sections; criteria mode resolves the same rows (build/review symmetry probe)
   - *index-absent:* skill infers from repo context, OFFERS persistence, zero unprompted writes (`git status --porcelain` empty after a declined offer)
   - *mixed/external-row:* external row routes; a deliberately broken row is surfaced with an offered fix, never silent
   - *setup idempotency:* bootstrap run twice → `git diff --stat` empty on the second run (both plugins' setup)
   - *trivial-scale:* trivial task → no standards fetch beyond ambient (grounding-depth gate probe)
   - *personal overlay (reviewer F3):* fixture with a `.local.md` that ADDS one rule and directly CONFLICTS on another → added rule applied with layer provenance named; conflicting rule loses to team (precedence inversion probe)
   - *user-global layer (reviewer F2/F3):* fixture with `~/.claude/standards/` populated (temp HOME) → layer discovered and applied; **empirically record whether the outside-cwd Read prompts** — the Brief's verified prompt-free fact covers the working directory only. If it prompts, STOP at the user-approval gate: accepted-cost note in the contract README vs design change is the user's call
   - *canary rules (DA-F2 — anti-theater probe, REQUIRED in every grounding fixture):* each fixture standard carries a distinctive counter-default rule the model would not produce unprompted (e.g. "repository pattern forbidden; use direct DbContext"). Assert the produced plan's CONTENT complies — not merely that sections are cited; the trivial-scale fixture's plan must NOT mention the canary. Review side: a fixture diff violating the canary must be flagged by the grounded criteria resolution. Citation-only compliance = FAIL
   - *version skew (DA-F3):* fixture index at contract 1.1.0 (simulated) read by a plugin bundling 1.0.0 → best-effort read + "update the plugin" message, NO migration offer, no nagging loop between the two setups
   - *pre-existing README (DA-F5):* fixture with a hand-authored `docs/standards/README.md` lacking the `standards-contract` key → treated as inference source, setup requires explicit confirmation before conversion, never overwrites
3. **Playbook gates:** per-plugin migration gate + plugin-acceptance security review (no code execution added beyond the sync script — reviewed; no egress; no secrets; cache-isolation respected: skills reference only `${CLAUDE_PLUGIN_ROOT}` paths).

**Sanity Check:**

- Both `claude plugin validate --strict` runs exit 0
- Every fixture-exercise row above recorded with PASS + evidence pointer in this PLAN before merge
- `grep -rn "docs/standards" plugins/planning plugins/review --include="*.md" -l` hits only files that present the path as the *documented default*, never a hardcoded absolute/org path
- `git diff --name-only origin/main -- plugins/ | xargs grep -lniE "melodic-software|kyle|D:\\\\|/Users/|C:\\\\"` returns 0 hits (sweeps ALL changed plugin files incl. evals and context files — reviewer F6)

## Blast radius

**MEDIUM-HIGH.** Triggers matched: new convention + enforcement mechanism (CI drift job), infrastructure change (ci.yml), architecture decision spanning multiple plugins (new cross-plugin contract). ~20 files, two plugin version bumps, one new CI job. Reversible via git revert pre-merge; convention becomes load-bearing only after consumers adopt. Formal stress-test (Step 4 `/devils-advocate`) REQUIRED.

## Stress-test summary

Two fresh-context passes, both verified against actual repo files before application:

1. **Plan-reviewer (Step 3):** 1 CRITICAL (planning:setup's double ignore-file prohibition vs the shipped overlay ignore line — reconciled via setup-owned `<standards_dir>/.gitignore` + scoped prohibition), 2 IMPORTANT (user-global outside-cwd read-prompt unverified → Phase 5 empirical probe + approval gate; overlay/user-global layers unexercised → fixture rows added), 5 SUGGESTIONS (precedent citation corrected, changelog grep fixed, concrete diff-driven grep sweep, D4 basis restated with named residual, compaction/multi-task ambient guard added). All folded in.
2. **Devils-advocate (Step 4):** 1 CRITICAL — the pilot as Brief-scoped cannot fully validate build/review symmetry because quality-gate's criteria mode is reference-only and the verdict-issuing modes (self/code/security/pr) never route through it; resolution is a user scope decision at approval (Option A: also rewire quality-gate Step 1 item 3 "What conventions apply?" through the index — one sentence, all modes inherit; Option B: keep Brief scope, downgrade the symmetry claim to "shared resolution ladder" and push verdict grounding to wave 2). 3 HIGH folded in: grounding-theater probes (canary-rule fixtures), directional version-skew semantics (never downgrade, "update the plugin"), frontmatter-semver + changelog enforcement in `--check-bump`. 5 MEDIUM folded in: normative index-presence test, resolution root + forward-slash paths, tripwire `*.test.sh` markers (evals are NOT CI-run — named gap), size guidance + selective section reads, delimited-ladder pointer discipline. 2 LOW folded in: setup short-circuit when conformant, no relative links in the canonical README. 1 accepted cost: lockstep manifest bumps at fleet scale (D1, generalization deferred with trigger).

No research-iterate round needed: findings were contract-text and probe-design gaps, not contested external claims; zero external-evidence disputes survived verification.

## Execution shape

Sequential recommended: 1 → 2 → 3 → 4 → 5.

Phases 3 and 4 are file-disjoint (different plugins) and parallel-capable (~200 LOC each — above the material threshold), but both are judgment-heavy skill-prose edits that depend on the full design context; parallel worker briefs would have to duplicate that context, and drift between the two consumers is precisely the failure mode this topic exists to remove. Cost note: sequential forgoes ~1 phase of wall-clock saving; 2 parallel agents would roughly double token spend on the heaviest phases. Fallback unaffected (already sequential).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | contract prose; single source for everything downstream; judgment-heavy |
| 2 | main-session | small scripts + CI wiring; test-first; tightly coupled to Phase 1 output |
| 3 | main-session | judgment-heavy skill prose; full design context required |
| 4 | main-session | same; symmetry with Phase 3 wording matters |
| 5 | main-session + fresh-context sub-agents for fixture exercises | exercises need clean context to be honest probes; security review dispatches per playbook |

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| D1 `[EXEC-SHAPE]` Sync = dedicated script (hook-utils shape: `sync`/`--check`/`--check-bump`, opt-in by file presence) + registry entry + CI job — not a `validate-plugin-contracts.mjs` extension | Phase 2 file list | The byte-identical precedents read this session are hook-utils and artifact-protocol — NOT topic-docs, whose `reference/topic-docs.md` copies are per-plugin tailored bindings with no sync (Brief's "topic-docs precedent" citation corrected, reviewer F4). `sync-hook-utils.sh` scales by presence-glob (fleet waves add no script edits) and `--check-bump` mechanically enforces the version-bump acceptance criterion; the mjs `lifecycleProtocolCopies` alternative hardcodes the plugin list and has no bump check. Named cost accepted (DA-F10): every canonical edit forces manifest+changelog bumps in ALL carrying plugins — fine at 2, friction at fleet scale. Deferred (trigger: first fleet wave): generalize the two clone-shaped sync scripts into one src/glob-parameterized script and revisit bump tooling |
| D2 `[EXEC-SHAPE]` Contract README carries `standards-contract: <semver>` frontmatter | Phase 1 README | T6 (design, RESOLVED) requires setup to compare "index frontmatter vs bundled contract"; the bundled copy must be self-describing offline — CHANGELOG isn't synced. Mirrors the index's own key |
| D3 `[EXEC-SHAPE]` Grounding step placed at top of architect Step 2, not Step 1 | Phase 3 SKILL.md edit | Step 2 is where formulation inputs gather; a Step 1 gate would read as blocking (anti-waterfall constraint C in Brief); acceptance criterion binds grounding to plan formulation output |
| D4 (superseded at approval) Quality-gate rewire = `criteria.md` + Shared-inputs line **+ Step 1 item 3** | Phase 4 scope | Originally confined to criteria mode per Brief; devils-advocate showed verdict-issuing modes never route through `criteria.md` (grounding would materialize only on explicit criteria invocation). User approved the one-sentence Step 1.3 extension (DA-F1 Option A, 2026-07-17) so all modes inherit |
| D5 `[EXEC-SHAPE]` Bootstrap procedure lives normatively in the contract README; both setup skills implement by binding reference | Phase 1 README section; Phases 3–4 setup prose stays thin | Single-home rule (topic-docs convention, read this session); T6 makes migration semantics contract semantics; prevents 2→fleet procedure drift |
| D6 `[EXEC-SHAPE]` Binding filename `reference/standards-contract.md` | Phases 2–4 references | `reference/standards.md` would collide semantically with consumer standards files; artifact-protocol precedent names the copy after the contract content. Cheap to rename before merge — flag if you prefer `standards.md` |
| D7 `[EXEC-SHAPE]` Version bumps minor: planning → 0.13.0, review → 0.10.0 | Phases 3–4 | Additive features (new step, new skill), no breaking change to existing behavior |
| D8 `[EXEC-SHAPE]` Test seam = script test (test-first) + registered CI drift job + eval cases + fixture-repo exercises; no unit seams inside skill prose | Phases 2, 5 | T7 (design, directional) fixes the seam at the highest level; `*.test.sh` + evals.json are the repo's two existing test surfaces (read this session); prose changes get exercise-based verification with a documented test-after carve-out |

## Open questions

- **DA-F1 RESOLVED (user-approved 2026-07-17): Option A** — quality-gate Step 1 item 3 rewired through the index; all review modes inherit grounded conventions. Phase 4 SKILL.md row carries the work item.
- Wave-2 rollout inventory stays USER-RESERVED (Brief); it inherits the named residuals: sync-script generalization + bump tooling deferred to the first fleet wave (D1).

## Handoff to implementation

### User-approval gates

- Any deviation from `contract-spec.md` content discovered mid-write (beyond D2) — stop and surface.
- Fixture-exercise FAIL that suggests contract-schema change (not just prose fix) — stop; contract edits post-approval re-open design.
- Security-review finding at Phase 5 — stop and surface.
- User-global-layer exercise shows an outside-cwd Read permission prompt — stop; accepted-cost note vs design change is the user's call (reviewer F2).

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→5, main-session (table above). Phase 2 script work is test-first. PLAN.md status tags advance per phase; PLAN edits main-session only.

### Mechanical work

- Commit boundary per phase (Conventional Commits; squash-merge PR titled per repo rule). Phase 1+2 may share one commit if landed together (structural spine), 3 and 4 each their own.
- Verification checkpoint per phase = its Sanity Check block, run before the phase commit.
- Fresh-docs fetch at the top of Phases 3 and 4 (skills page) and before any ci.yml edit (hooks/settings pages not needed).
- Sequential fallback: n/a (already sequential).
