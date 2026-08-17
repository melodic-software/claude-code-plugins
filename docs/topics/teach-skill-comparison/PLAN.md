# teach-skill-comparison

## Brief

### TLDR

Make `education:teach` the best general-purpose learning coach for any repo and any subject by combining the best of Matt Pocock's upstream `teach` skill with this marketplace's machinery: repatriate his storage-strength pedagogy, flip lessons to interactive HTML with a workspace assets library, default every lesson to research-grounded teaching through a presence-gated composition ladder, make the workspace root configurable with an OS-convention default, add spaced review — validated by before/after dogfood runs and evals.

### Goal

Two-way audit outcome of the comparison (see `.work/teach-skill-comparison/COMPARISON.md` and `COMPOSITION-DESIGN.md`, research at `.work/teach-skill-comparison/research-pocock-rationale/RESEARCH.md`): adopt what he kept that we dropped, keep our defensible divergences, and out-execute his acknowledged gaps (no assessment, no review scheduling) using state machinery only we have. Every change stays within the plugin philosophy (consumer/machine/repo agnostic; presence-gated cross-plugin composition with documented fallbacks) and serves downstream consumers through configuration, not hard-coded variants.

### Constraints

- Plugin philosophy: no bare cross-plugin references — every composition is "if installed" with a documented fallback; behavior never depends on publisher names or machine paths; `frontend-design` remains optional-external, never a dependency.
- Learning state is user-specific by default; team sharing is a flavor (Claude artifacts when available; committed repo path by explicit project declaration), never the default.
- Durable artifacts (`reference.md`, learning records, glossary) stay markdown — the diffable source of truth; the HTML flip applies to lessons only.
- Research grounding = consensus from official/authoritative/trusted sources (the `discovery:research` tier discipline); never parametric recall for lesson claims.
- OS conventions with proper platform casing for any user-visible directory (Windows Documents known folder; `xdg-user-dir DOCUMENTS` on Linux; `~/Documents` on macOS).
- Existing plugin-data workspaces must remain readable (dual-root scan or one-time offered migration); slug-canonicalization and collision guards apply at every root.
- Documented hazards, not silent behavior: gitignored in-repo roots fragment across worktrees; temp roots die with the session; committed roots put personal state in shared repos (explicit team choice only).
- Baseline dogfood runs BEFORE any skill edit; the after-run proves skill reload with a canary marker; both runs use the same scripted learner persona (`/verification:measure` baseline discipline).

### Acceptance criteria

1. `docs/upstream/mattpocock-skills.md` carries a corrected `teach` → `education:teach` Derived attribution row (taken/rejected/added), and the v1.2 map row 22 is corrected to match.
2. Teach SKILL.md pedagogy includes fluency-vs-storage strength, desirable difficulty (retrieval practice, spacing, interleaving — interleaving scoped to skills practice), the knowledge/skills difficulty asymmetry, and the equal-length quiz-answer rule.
3. Lessons default to interactive, self-contained HTML with a per-workspace `assets/` component library (shared stylesheet first; answer-shuffling quiz component so correct answers are never positionally detectable); `reference.md`, records, and glossary stay markdown; the existing lesson.html identity/meta rules survive.
4. A three-tier research-grounding ladder is in the skill: tier 1 default per-lesson grounding via `/discovery:research` (fallback: inline fetch + `/context7:lookup` + `/firecrawl:firecrawl`), tier 2 workspace seeding via `/discovery:research-deep`/dynamic workflows, tier 3 huge-subject corpus via `/knowledge:map-corpus` + digest skills with RESOURCES.md pointing at produced slices — all presence-gated with fallbacks; `/discovery:blindspot`, `/dometrain:grounding`, `/x:read`, `/education:quiz-me`, `/visualization:visualize`, Artifact-share flavor composed per `.work/teach-skill-comparison/COMPOSITION-DESIGN.md`.
5. Workspace-root resolution ladder implemented: project declaration → plugin userConfig (surfaced/validated via `education:setup`) → ask-once-when-in-doubt → OS Documents default (proper casing) → plugin-data fallback; `scripts/list-workspaces.sh` (and resume/status) resolves all roots; migration/compat behavior stated in the skill.
6. Spaced review: `resume` and `status` surface due-for-review concepts from learning-record age × domain velocity; floor revisit language ties into the ported spacing doctrine.
7. Open-lesson affordance: after writing a lesson, offer to open it via the platform-appropriate command (permission-gated).
8. Skill passes `/skill-quality:check`; `evals/evals.json` extended to cover the new behaviors; docs-hygiene pass keeps SKILL.md within budget discipline (two-budgets lens).
9. Before/after dogfood evidence captured under the same scripted persona ("vibe coder learning this repo") with a written comparison; the after-run's canary proves live reload.
10. All work pushed to `claude/teach-skill-comparison-h3rpag`; each phase lands as its own reviewed commit.

Execution contract: implementation proceeds item-by-item in impact/value order (pedagogy + research ladder → HTML lessons/assets → workspace root → spaced review → quiz/open-lesson affordances → provenance + hygiene); an item is closed when its acceptance criterion is met, verified, and committed.

### Captured assumptions

- Skills in this session load from the live repo working tree (observed: invoked skills report repo-path base directories); the after-dogfood canary re-verifies before the comparison is trusted.
- `education:quiz-me` composition changes teach only; quiz-me itself is not modified in this scope.
- His aihero announcement articles / full X threads remain unread verbatim (egress-blocked); repo-mirrored docs pages carry the substance. Not load-bearing for any acceptance criterion.

### Out of scope

- External-system storage adapters (Notion, wikis, MCP-backed stores) — the root seam and RESOURCES.md pointers leave the door open; recorded as deferred, not rejected.
- Codex `agents/openai.yaml` sidecar (standing marketplace precedent: no Codex target).
- Modifying sibling skills (`quiz-me`, `explain`, knowledge/discovery plugins) beyond documented composition seams.
- A spaced-repetition scheduler beyond resume/status surfacing (no background jobs, no notification machinery).

### Deferred questions

- Q-D1: External storage adapter shape (arbiter: `/planning:plan`, post-V1) — depends on demand from downstream consumers.
- Q-D2: Verbatim aihero/X source texts (arbiter: USER-RESERVED) — supply from an unproxied session if announcement-level framing is ever needed; current evidence suffices for this scope.

## Plan

Standards grounding: docs/PLUGIN-PHILOSOPHY.md (design boundary, naming, presence-gated composition — read this session), docs/MIGRATION-PLAYBOOK.md, upstream provenance discipline per docs/upstream/mattpocock-skills.md, skill QA via /skill-quality:check. Baseline evidence: `.work/teach-skill-comparison/dogfood/baseline/FINDINGS.md` (F1–F15).

### Phase 1: Pedagogy port + research-grounding ladder [TODO]

Core behavior slice (integration-first). SKILL.md "Pedagogy — Three Layers": add fluency-vs-storage strength (his terms quoted, Bjork's retrieval/storage noted), desirable difficulty (retrieval practice, spacing, interleaving — interleaving scoped to skills practice), the knowledge/skills difficulty asymmetry. Replace the Knowledge layer's grounding bullet with the three-tier ladder (tier 1 `/discovery:research` default w/ inline-fetch + `/context7:lookup` + `/firecrawl:firecrawl` fallbacks; tier 2 `/discovery:research-deep`/dynamic workflows for seeding/big subjects; tier 3 `/knowledge:map-corpus` + digest skills w/ RESOURCES.md pointers), all presence-gated. `/discovery:blindspot` intake for unknown-territory learners; `/dometrain:grounding`, `/x:read` as gated resource sources. Compress the mission interview when the opening message already answers fields (F11). context/exercises.md + context/assessment.md: equal-length quiz answers rule. context/resources.md: scope verification for codebase mode (F7).

**Sanity Check:** `grep -c "storage strength" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "discovery:research" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "if installed\|when installed\|presence" plugins/education/skills/teach/SKILL.md` covers every cross-plugin name added (grep each of map-corpus, blindspot, dometrain, x:read → each within 3 lines of a guard phrase); `grep -c "equal" plugins/education/skills/teach/context/exercises.md` ≥ 1.

### Phase 2: HTML-first lessons + assets library [TODO]

context/lessons.md: flip the lesson default to interactive self-contained HTML (quizzes, anchors, openable), markdown the documented exception where interactivity pays nothing; keep the existing lesson.html identity/meta + replacement rules but state them ONCE (dedupe the three restatements, F12); give the HTML-lesson branch the authoring guidance weight (Teach/Practice in HTML, quiz blocks). SKILL.md workspace layout: add `assets/` to the topic workspace (shared stylesheet first; answer-shuffling quiz component so correct answers are never positionally detectable — adopts upstream doctrine + fixes his #335 class of bug); reuse-first: read `assets/` before authoring, extract reusable pieces. References/records/glossary stay markdown (state explicitly). Artifact-share flavor: presence-gated "publish lesson as a Claude artifact when the capability exists" for team sharing.

**Sanity Check:** `grep -c "assets/" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -ci "shuffl" plugins/education/skills/teach/context/lessons.md` ≥ 1; replacement rule stated once: `grep -c "never both" plugins/education/skills/teach/SKILL.md` ≤ 1 with lessons.md carrying the full rule; `grep -ci "reference.md.*markdown\|stays markdown" plugins/education/skills/teach/context/lessons.md` ≥ 1.

### Phase 3: Workspace-root resolution ladder [TODO]

SKILL.md "Workspace layout": replace the fixed `${CLAUDE_PLUGIN_DATA}` root with the resolution ladder — (1) project declaration (CLAUDE.md/rules convention), (2) plugin userConfig `workspace_root`, (3) ask-once-when-in-doubt, (4) OS-convention default: Documents known folder (Windows `[Environment]::GetFolderPath('MyDocuments')`, macOS `~/Documents`, Linux `xdg-user-dir DOCUMENTS` → `~/Documents` fallback) + properly-cased `Claude Learning` home, (5) `${CLAUDE_PLUGIN_DATA}` fallback (headless/unset, F15) and compat home. Slug canonicalization + collision guards apply at every root (unchanged). Documented hazards: worktree fragmentation (gitignored in-repo roots), temp mortality, personal-state-in-shared-repo. Compat: `scripts/list-workspaces.sh` scans all resolvable roots (+ tests updated); resume/status resolve across roots; one-time offered migration note. education plugin manifest/userConfig: add `workspace_root`; `education:setup check` reports it.

**Sanity Check:** `bash plugins/education/skills/teach/scripts/list-workspaces.test.sh` exits 0; `grep -c "xdg-user-dir" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -ci "worktree" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "workspace_root" plugins/education/.claude-plugin/plugin.json` ≥ 1 (or the manifest file the plugin actually uses — verify at execution).

### Phase 4: Spaced review + affordances [TODO]

SKILL.md resume/status: surface due-for-review concepts from learning-record age × domain velocity (ties to Staleness + the ported spacing doctrine); status shows a due-for-review column. context/assessment.md ZPD calc: floor revisit becomes scheduled-by-age. Open-lesson affordance: after writing a lesson, offer to open it platform-appropriately (permission-gated). `/education:quiz-me` composition: quiz reports usable as learning-record evidence (teach side only). `/visualization:visualize` + dataviz constraints named for in-lesson diagrams.

**Sanity Check:** `grep -ci "due.*review\|spaced" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "quiz-me" plugins/education/skills/teach/SKILL.md` ≥ 1 within 3 lines of a presence guard; `grep -ci "open the lesson\|open it" plugins/education/skills/teach/context/lessons.md` ≥ 1.

### Phase 5: Baseline-findings remediation sweep [TODO]

Residual F-items not absorbed above: F1 smart-default covers whole-repo/deictic subjects (route to codebase; naming rule: derive a stable content name, e.g. repo basename + "overview", recorded as raw name); F2 deictic slug rule; F3 rename the codebase action argument to `<topic>` (or state the mapping explicitly); F4 reorder New Workspace: mission interview BEFORE workspace creation; F5 add GLOSSARY.md (deferred-until-demonstrated, stated) + NOTES.md (seeded from interview constraints) creating steps; F6 mission-title identity duty stated in context/mission.md; F8 relational topic-docs pointer (docs/conventions/topic-docs/) replacing the raw URL — keep a URL fallback for non-repo consumers; F9 empty/contradictory guidance-file handling in Codebase Mode; F10 prior-knowledge record via scan-and-increment + link assessment.md from Session Flow; F13 `_Avoid_` line marked optional in context/glossary.md.

**Sanity Check:** each F-item verified by targeted grep at execution (per-item command recorded in the commit); ordering check: `grep -n "mission interview" plugins/education/skills/teach/SKILL.md` line < `grep -n "Create the workspace" ...` line.

### Phase 6: Provenance correction [TODO] (parallel-safe — file-disjoint)

docs/upstream/mattpocock-skills.md: move `teach` out of "Not adopted"; add a Derived attribution row (taken: workspace vocabulary, FORMAT-spec content near-verbatim, K-S-W/ZPD/community delegation, learning-record doctrine; rejected: cwd-as-workspace, Codex sidecar, HTML references; added: codebase mode, primer, assess, staleness, evals, collision guards — now also re-adopted: storage-strength pedagogy, HTML lessons, assets). Correct v1.2 map row 22 (CONVERGENT → Derived). Cite this topic as the audit.

**Sanity Check:** `grep -c "education:teach" docs/upstream/mattpocock-skills.md` ≥ 1 in the attribution table; `grep -c "teach.*(education plugin covers)" docs/upstream/mattpocock-skills.md` = 0.

### Phase 7: Evals, QA gates, hygiene [TODO]

Extend `evals/evals.json`: research-ladder tier selection, workspace-root resolution, HTML-lesson default, spaced-review surfacing, deictic-subject routing. Run `/skill-quality:check` on the skill; docs-hygiene two-budgets pass on SKILL.md (target: body growth offset by F12 dedupe + disclosure pushes; hard ceiling: SKILL.md stays lint-clean and within the repo's skill listing budget checks). Changelog + version bump per repo convention (education CHANGELOG parity gate).

**Sanity Check:** `check-jsonschema`/repo eval lint passes on evals.json (command per repo CI); `/skill-quality:check` reports pass; `bash scripts/check-changelog-parity.sh` (or the CI-invoked equivalent) exits 0.

### Phase 8: After-dogfood + comparison [TODO]

Insert a canary marker in SKILL.md (temporary comment or version string readable by the run), re-run the identical persona script via a fresh-context agent (same sanctioned plugin-data substitution → `dogfood/after/`), verify the canary surfaced (proves live reload), remove the canary. Write `dogfood/COMPARISON-BEFORE-AFTER.md`: session shape deltas, artifact deltas, findings resolved/introduced, verdict against the Brief's goal. Distilled comparison recorded here in PLAN.md; memory-slice paths never cited in the committed doc beyond the topic-docs convention.

**Sanity Check:** `dogfood/after/` contains transcript + workspace; canary confirmed in the after-transcript then absent from SKILL.md (`grep -c "<canary-string>" plugins/education/skills/teach/SKILL.md` = 0 post-cleanup); COMPARISON-BEFORE-AFTER.md exists with a per-finding resolved/unresolved table.

## Blast radius

MEDIUM — one plugin's instruction surface + one script, no runtime code elsewhere; but two consumer-visible behavior changes (default lesson format, default workspace location) and a broad new composition surface. Mitigations: compat scanning of legacy plugin-data workspaces, presence-gated composition with fallbacks, evals + before/after dogfood evidence.

## Stress-test summary

(To be filled after Step 3 plan-reviewer + Step 4 devils-advocate rounds.)

## Execution shape

Sequential main-session for Phases 1–5 and 7–8 (they share SKILL.md/context files — file-overlap forbids parallel), Phase 6 parallel-safe (docs/upstream only, zero overlap) and may run alongside any phase. Per-phase routing: 1–5 main-session (judgment-heavy instruction authoring); 6 main-session or sub-agent (mechanical, disjoint); 7 main-session with `/skill-quality:check` as its own invocation; 8 fresh-context sub-agent for the run + main-session for the comparison. Sequential fallback: everything main-session in phase order. Cost note: only Phase 8 spawns an agent by design.

## Open questions

None at approval time beyond the Brief's two deferred questions (Q-D1 external storage adapter — post-V1; Q-D2 verbatim upstream announcement texts — USER-RESERVED, not load-bearing).

## Handoff to implementation

### User-approval gates

- Phase 3's userConfig key name and the OS-default folder name (`Claude Learning`) are user-visible — surfaced in the Decisions table; flag before Phase 3 lands if the user wants different naming.
- Any mid-flight discovery that legacy-workspace compat cannot be kept scan-only (i.e. a forced migration) — stop and ask.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Phase order per Brief's impact/value contract with integration-first core (Phase 1) and file-overlap-driven sequencing; Phase 6 slotted anywhere.
- [EXEC-SHAPE] Baseline findings distributed into phases 1–3 where thematically owned, residual sweep in Phase 5.
- [EXEC-SHAPE] Canary mechanism for reload proof: temporary marker string, removed post-verification.

### Mechanical work

One commit per phase minimum, each with its sanity-check evidence in the message; push after every phase (`git push -u origin claude/teach-skill-comparison-h3rpag`); changelog/version bump rides Phase 7; PLAN.md phase tags advanced main-session-only.
