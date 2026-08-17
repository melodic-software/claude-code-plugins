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

### Phase 1: Pedagogy port + research-grounding ladder [DONE]

Core behavior slice (integration-first). SKILL.md "Pedagogy — Three Layers": add fluency-vs-storage strength (his terms quoted, Bjork's retrieval/storage noted), desirable difficulty (retrieval practice, spacing, interleaving — interleaving scoped to skills practice), the knowledge/skills difficulty asymmetry. Replace the Knowledge layer's grounding bullet with the graduated ladder — **tier 0 (DA #3): repo files Read this turn (codebase mode) and already-verified RESOURCES.md citations satisfy grounding for narrow/slow-domain claims — no dispatch; escalate to tier 1 on contested, broad, or fast-domain claims, capped at roughly one research dispatch per session unless the subject shifts (never parametric recall at any tier — the constraint is which fetch, not whether)**; tier 1 `/discovery:research` w/ inline-fetch + `/context7:lookup` + `/firecrawl:firecrawl` fallbacks (each itself presence-gated, chain terminates at built-in WebSearch/WebFetch); tier 2 `/discovery:research-deep`/dynamic workflows for seeding/big subjects; tier 3 `/knowledge:map-corpus` + digest skills w/ RESOURCES.md pointers — all cross-plugin names presence-gated. `/discovery:blindspot` intake for unknown-territory learners; `/dometrain:grounding`, `/x:read` as gated resource sources. Compress the mission interview when the opening message already answers fields (F11). context/exercises.md + context/assessment.md: equal-length quiz answers rule. context/resources.md: scope verification for codebase mode (F7).

**Sanity Check:** `grep -c "storage strength" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "discovery:research" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "if installed\|when installed\|presence" plugins/education/skills/teach/SKILL.md` covers every cross-plugin name added (grep each of map-corpus, blindspot, dometrain, x:read → each within 3 lines of a guard phrase); `grep -c "equal" plugins/education/skills/teach/context/exercises.md` ≥ 1.

### Phase 2: HTML-first lessons + assets library [DONE]

context/lessons.md: flip the lesson default to interactive self-contained HTML (quizzes, anchors, openable) **where the learner's host can render it — the format decision is platform-aware (DA #5): on headless/SSH/remote/cloud hosts with no browser, markdown stays the default (readable in terminal/chat), using the same host detection Phase 4 specifies for the open affordance**; markdown also remains the documented exception where interactivity pays nothing; keep the existing lesson.html identity/meta + replacement rules but state them ONCE (dedupe the three restatements, F12); give the HTML-lesson branch the authoring guidance weight (Teach/Practice in HTML, quiz blocks). **Asset assembly is scripted (DA #4): the coach authors lesson-body HTML; a bash splice step injects `assets/` contents (stylesheet, quiz component) into the self-contained file — assets never re-pass through model output after first authoring, preventing per-lesson token blowout and copy drift; stated as a MUST in lessons.md.** Shuffling defeats positional detection only — view-source can reveal grading logic; state as a known limitation, not a guarantee (DA #11). **Quiz result-return contract (reviewer #11):** in-page quizzes end in a copy-out result block the learner pastes back into chat for grading — the coach grades in conversation and records evidence in learning records, preserving the baseline's highest-value loop (F14c); the quiz component renders that block, never self-certifies learning. SKILL.md workspace layout: add `assets/` to the topic workspace (shared stylesheet first; answer-shuffling quiz component so correct answers are never positionally detectable — adopts upstream doctrine + fixes his #335 class of bug); reuse-first: read `assets/` before authoring, extract reusable pieces. References/records/glossary stay markdown — state as "the durable trio stays markdown". Artifact-share flavor: presence-gated "publish lesson as a Claude artifact when the capability exists". **Do NOT touch lessons.md's plugin-data path text (line ~52) here — that line is Phase 3's consumer sweep territory (reviewer #2).**

**Sanity Check:** `grep -c "assets/" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -ci "shuffl" plugins/education/skills/teach/context/lessons.md` ≥ 1; `grep -ci "copy.*back\|paste.*back" plugins/education/skills/teach/context/lessons.md` ≥ 1 (result-return contract present); replacement rule stated once in full (lessons.md carries it; SKILL.md `grep -c "never both"` ≤ 1); `grep -c "durable trio stays markdown" plugins/education/skills/teach/context/lessons.md` = 1 (token absent from current file — non-vacuous).

### Phase 3: Workspace-root resolution ladder [DONE]

**Work item 1 — pre-flight consumer sweep (contract migration; reviewer #2):** `grep -rn "CLAUDE_PLUGIN_DATA" plugins/education/` — every hit is a consumer to amend or explicitly keep: known today are `evals/evals.json` eval 1 ("under the plugin data dir" expectation — amend to root-ladder expectation), `context/lessons.md` HTML-placement rule (~line 52, also carries the raw topic-docs URL → replace with relational `docs/conventions/topic-docs/` pointer + URL fallback, F8), SKILL.md Resume/Status header (~line 97), pre-compute block, and the layout section itself. Document each hit's disposition before editing.

**Ladder (each rung mechanically defined; follows the `knowledge.library_dir` precedent and the repo's config-cascade / consumer-config-layering conventions — cite both, reviewer #6):**

1. **Project declaration** — a learning-workspace root declared in the consuming project's CLAUDE.md or rules takes precedence (the exact prose pattern `knowledge.library_dir` already ships); documented shape: a "teach workspace root: <path>" declaration; resolved by the skill body (prose is not script-parseable, reviewer #5).
2. **`workspace_root` userConfig** — value grammar per `library_dir` precedent: absolute, `~`-home-relative, `${NAME}`/`%NAME%` env refs; relative resolves against the project; a root inside the consuming repo requires the project-declaration rung instead (repo-tree guard — Brief: committed roots by explicit project choice only). A surviving literal `${user_config.workspace_root}` placeholder means unset (quiz-me:37 convention).
3. **Ask-once** — first workspace creation with rungs 1–2 unset in an interactive session: one question. **Persistence (reviewer #1):** the answer lands in a pointer file `${CLAUDE_PLUGIN_DATA}/workspace-root` (also stores the migration-offer outcome, reviewer #12) — never a `pluginConfigs` write (philosophy forbids); the native userConfig prompt is additionally recommended to the user via `education:setup`. Non-interactive/headless sessions skip this rung silently.
4. **OS Documents default** — rung fires ONLY when the Documents directory already exists AND ≠ `$HOME` (reviewer #3: bare `xdg-user-dir` echoes `$HOME` when unconfigured; never silently create Documents): Windows via the Documents known folder resolved per the repo's `docs/conventions/windows-path-emit/` convention (`scripts/emit-windows-path.sh` posture; OneDrive-redirected and space-bearing paths converted, fail-loud — reviewer #4; record the honest manual-verification gap for Windows in the phase commit); macOS `~/Documents`; Linux `xdg-user-dir DOCUMENTS` with the ≠`$HOME` guard. Home inside it: properly-cased `Claude Learning/`.
5. **`${CLAUDE_PLUGIN_DATA}` fallback** — headless/unset/no-Documents (F15) and the compat home for every existing workspace.

**Mode-split default (DA #2):** the OS-Documents default applies to `topic` workspaces only; **`codebase` workspaces stay plugin-data by default** — Documents roots are commonly cloud-synced (OneDrive/iCloud), and codebase lessons embed repo snippets that must not silently leave the machine for private repos; a codebase workspace lands at a user-chosen root only via explicit rung-1/2 configuration. Hazards list gains cloud-synced roots: machine-scoped slugs mean the same repo on two machines gets sibling workspaces in one synced root (no illusory continuity — documented), and sync conflicts on `learning-records/NNNN` are called out. **Cross-root semantics (reviewer #12):** for a given `<project-slug>/<mode>/<topic>`, the ladder-highest root wins; duplicates at lower roots are surfaced (never merged); migration is a one-time offer whose outcome persists in the rung-3 pointer file — **the pointer is a machine-local cache only (DA #6): before asking, an existing `Claude Learning/` home at the rung-4 location (or a configured root) is adopted without asking; when plugin-data is unavailable (F15) the ask-once rung falls through silently rather than erroring**. **Worktree slugs (reviewer #10):** derive the canonical project path via `git rev-parse --git-common-dir` when inside a worktree so all worktrees of one repo share a workspace; compat: `list-workspaces.sh` also scans old per-worktree slugs and labels them. **Script contract (redesigned per DA #1 — CRITICAL):** the `${user_config.workspace_root}` token NEVER appears in the pre-compute line — empirically, a surviving literal kills bash (`bad substitution`) before any fallback and trips the #1687 worktree-isolation guard in the default unset state. Instead, per the quiz-me:37 pattern: the token renders in a body table ("surviving literal = unset"), pre-compute passes only `CLAUDE_*` variables (plugin-data probe, unchanged), and the skill body re-invokes `list-workspaces.sh` as an ordinary Bash call with body-resolved roots as arguments; the SKILL.md pre-compute line and the script signature change in ONE atomic commit (DA #8), and the skill distinguishes script exit 2 (probe broken → manual glob before creating any workspace) from a genuine "none" (DA #8). Tests cover the argument matrix, placeholder-unset, `$HOME`-guard, and pre-compute composition (unset, set-with-spaces). Rung 2 is grep-provable but not exercisable in the dogfood harness — recorded as an acknowledged gap beside the Windows one (DA #10). **Classification rationale (reviewer #7):** record in the education CHANGELOG (and README) why learning workspaces are user documents rather than machine state — the deliberate, documented deviation from the philosophy's plugin-data default, so the fleet audit sees a decision, not drift. `education:setup`: add `workspace_root` to plugin.json userConfig; setup's description + option enumeration edited (reviewer #13).

**Sanity Check:** `bash plugins/education/skills/teach/scripts/list-workspaces.test.sh` exits 0 (matrix includes placeholder-unset + `$HOME`-guard cases); `grep -c "git-common-dir" plugins/education/skills/teach/SKILL.md` ≥ 1 (token absent today — non-vacuous); `grep -c "workspace_root" plugins/education/.claude-plugin/plugin.json` ≥ 1; `grep -c "raw.githubusercontent" plugins/education/skills/teach/context/lessons.md` = 0; `grep -rn "under the plugin data dir" plugins/education/skills/teach/evals/evals.json` = 0 (eval 1 amended); CHANGELOG carries the classification rationale (`grep -ci "user documents\|machine state" plugins/education/CHANGELOG.md` ≥ 1).

### Phase 4: Spaced review + affordances [TODO]

SKILL.md resume/status: surface due-for-review concepts from learning-record age × domain velocity (ties to Staleness + ported spacing doctrine). **Status budget reconciled (reviewer #16a):** status stays one-line-per-workspace using filename + mtime heuristics only (record slugs and ages need no file bodies); the deeper due-for-review detail loads only on `resume` of that workspace. context/assessment.md ZPD calc: floor revisit becomes scheduled-by-age. Open-lesson affordance **(reviewer #15)**: after writing a lesson, offer to open it — macOS `open`, Linux `xdg-open` (degrade visibly when absent), Windows `start`/`explorer.exe` from Git Bash — and skip the offer entirely on remote/web/cloud hosts where opening is meaningless (hand back the path). `/education:quiz-me`: same-plugin sibling — composed WITHOUT a presence gate (reviewer #8); quiz reports usable as learning-record evidence. `/visualization:visualize` for concept diagrams with the native-mermaid fallback stated (reviewer #14); dataviz constraints named for in-lesson charts.

**Sanity Check:** `grep -ci "due.*review" plugins/education/skills/teach/SKILL.md` ≥ 1; `grep -c "quiz-me" plugins/education/skills/teach/SKILL.md` ≥ 1 and NOT within 3 lines of an "if installed" guard (same-plugin, reviewer #8); `grep -ci "xdg-open" plugins/education/skills/teach/context/lessons.md` ≥ 1 with `open`/`start` siblings present; `grep -ci "mermaid" plugins/education/skills/teach/SKILL.md` ≥ 1.

### Phase 5: Baseline-findings remediation sweep [TODO]

Residual F-items not absorbed above: F1 smart-default covers whole-repo/deictic subjects (route to codebase; naming rule: derive a stable content name, e.g. repo basename + "overview", recorded as raw name); F2 deictic slug rule; F3 rename the codebase action argument to `<topic>` (or state the mapping explicitly); F4 reorder New Workspace: mission interview BEFORE workspace creation; F5 add GLOSSARY.md (deferred-until-demonstrated, stated) + NOTES.md (seeded from interview constraints) creating steps; F6 mission-title identity duty stated in context/mission.md; F8 relational topic-docs pointer (docs/conventions/topic-docs/) replacing the raw URL — keep a URL fallback for non-repo consumers; F9 empty/contradictory guidance-file handling in Codebase Mode; F10 prior-knowledge record via scan-and-increment + link assessment.md from Session Flow; F13 `_Avoid_` line marked optional in context/glossary.md.

**Sanity Check (pre-specified, non-vacuous — reviewer #9):** F4 ordering scoped to the New Workspace section: `awk '/### New Workspace/,/### Resume/' plugins/education/skills/teach/SKILL.md` shows the mission-interview step numbered BEFORE the create-workspace step; F1: `grep -ci "whole repo\|entire repo\|this repo" plugins/education/skills/teach/SKILL.md` ≥ 1 inside the smart-default rules; F5: `grep -c "NOTES.md" plugins/education/skills/teach/SKILL.md` ≥ 1 within the New Workspace or Session Close steps (seeding step exists); remaining F-items get their per-item grep recorded in the phase commit message.

### Phase 6: Provenance correction [TODO] (parallel-safe — file-disjoint)

docs/upstream/mattpocock-skills.md: move `teach` out of "Not adopted"; add a Derived attribution row (taken: workspace vocabulary, FORMAT-spec content near-verbatim, K-S-W/ZPD/community delegation, learning-record doctrine; rejected: cwd-as-workspace, Codex sidecar, HTML references; added: codebase mode, primer, assess, staleness, evals, collision guards — now also re-adopted: storage-strength pedagogy, HTML lessons, assets). Correct v1.2 map row 22 (CONVERGENT → Derived). Cite this topic as the audit.

**Sanity Check:** `grep -c "education:teach" docs/upstream/mattpocock-skills.md` ≥ 1 in the attribution table; `grep -c "teach.*(education plugin covers)" docs/upstream/mattpocock-skills.md` = 0.

### Phase 7: Evals, QA gates, hygiene [TODO]

`evals/evals.json`: AMEND existing evals invalidated by the root-ladder (eval 1's plugin-data expectation — verified amended in Phase 3's sweep) and EXTEND: research-ladder tier selection, workspace-root resolution, HTML-lesson default, spaced-review surfacing, deictic-subject routing. Equal-length quiz-answer rule verified in BOTH `context/exercises.md` and `context/assessment.md` (reviewer #16c). Run `/skill-quality:check`; docs-hygiene two-budgets pass on SKILL.md (body growth offset by F12 dedupe + disclosure pushes; hard ceiling: lint-clean + listing budget checks). **Version bump: education 0.7.0** (minor — two consumer-visible default changes; reviewer #16b) + CHANGELOG entry (parity gate `scripts/check-changelog-parity.sh` runs in CI).

**Sanity Check:** repo eval lint passes on evals.json; `/skill-quality:check` reports pass; `bash scripts/check-changelog-parity.sh` exits 0; `grep -ci "equal" plugins/education/skills/teach/context/assessment.md` ≥ 1; `grep -c "0.7.0" plugins/education/CHANGELOG.md` ≥ 1; **cumulative re-run of every Phase 1–6 sanity grep AFTER the docs-hygiene compression pass (DA #9) — compression must not reword asserted tokens.**

### Phase 8: After-dogfood + comparison [TODO]

Insert a canary marker in SKILL.md (temporary comment or version string readable by the run), re-run the identical persona script via a fresh-context agent (same sanctioned plugin-data substitution → `dogfood/after/`), verify the canary surfaced (proves live reload), remove the canary. **Verdict scoping (DA #7): this container cannot witness the Documents rung (no `xdg-user-dir`, no `~/Documents`), the HTML-openable branch (no browser), or full tier-1 research (restricted egress) — the comparison document states per-behavior what was witnessed live vs covered mechanically; the unwitnessable defaults are covered by `list-workspaces.test.sh` cases (fake Documents dir, stubbed `xdg-user-dir`, `$HOME`-guard) and eval assertions for format/root selection, never claimed as dogfood-proven.** Write `dogfood/COMPARISON-BEFORE-AFTER.md`: session shape deltas, artifact deltas, findings resolved/introduced, verdict against the Brief's goal. Distilled comparison recorded here in PLAN.md; memory-slice paths never cited in the committed doc beyond the topic-docs convention.

**Sanity Check:** `dogfood/after/` contains transcript + workspace; canary confirmed in the after-transcript then absent from SKILL.md (`grep -c "<canary-string>" plugins/education/skills/teach/SKILL.md` = 0 post-cleanup); COMPARISON-BEFORE-AFTER.md exists with a per-finding resolved/unresolved table.

## Blast radius

MEDIUM — one plugin's instruction surface + one script, no runtime code elsewhere; but two consumer-visible behavior changes (default lesson format, default workspace location) and a broad new composition surface. Mitigations: compat scanning of legacy plugin-data workspaces, presence-gated composition with fallbacks, evals + before/after dogfood evidence.

## Stress-test summary

Step 3 plan-reviewer (fresh context): 16 findings — 2 CRITICAL (ask-once persistence undefined; missing consumer pre-flight for the root migration), 10 IMPORTANT, 4 SUGGESTION. All verified against files and applied: Phase 3 rewritten (marker-file persistence, mechanical rung guards, windows-path-emit citation, consumer sweep as work item 1, script argument contract, library_dir-precedent grammar, classification rationale, cross-root precedence, git-common-dir worktree slugs), Phase 2 gained the quiz result-return contract, Phase 4 gained platform-enumerated open-lesson + no-gate-for-quiz-me + visualize fallback, vacuous sanity greps replaced with non-vacuous tokens, Phase 7 amends eval 1 and sets the 0.7.0 bump.

Step 4 devils-advocate (fresh context, prior findings excluded): verdict **GO-WITH-CHANGES** — 1 CRITICAL (user_config token in pre-compute = `bad substitution` load failure in the default unset state on the #1687 worktree path; empirically verified), 4 HIGH (cloud-synced Documents leaking codebase-mode snippets; per-lesson research dispatch cost; asset re-emission token blowout; HTML default dead on headless hosts), 4 MEDIUM, 3 LOW. All applied: tier-0 grounding rung + dispatch cap (Phase 1); scripted asset splice, platform-aware format decision, shuffling-limitation note (Phase 2); mode-split default (codebase stays plugin-data), cloud-sync hazards, pointer-as-cache + adopt-existing-root, atomic pre-compute/script commit + exit-2 handling, quiz-me-pattern body-side config resolution (Phase 3); cumulative grep re-run (Phase 7); scoped comparison verdict + mechanical coverage of unwitnessable defaults (Phase 8); localization note on the folder-name decision.

## Execution shape

Sequential main-session for Phases 1–5 and 7–8 (they share SKILL.md/context files — file-overlap forbids parallel), Phase 6 parallel-safe (docs/upstream only, zero overlap) and may run alongside any phase. Per-phase routing: 1–5 main-session (judgment-heavy instruction authoring); 6 main-session or sub-agent (mechanical, disjoint); 7 main-session with `/skill-quality:check` as its own invocation; 8 fresh-context sub-agent for the run + main-session for the comparison. Sequential fallback: everything main-session in phase order. Cost note: only Phase 8 spawns an agent by design.

## Open questions

None at approval time beyond the Brief's two deferred questions (Q-D1 external storage adapter — post-V1; Q-D2 verbatim upstream announcement texts — USER-RESERVED, not load-bearing).

## Handoff to implementation

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] `workspace_root` as the userConfig key | Phase 3 manifest + setup edits | Mirrors sibling precedents `library_dir` (knowledge) / `report_library_dir` (quiz-me) read this session |
| [EXEC-SHAPE] `Claude Learning` as the Documents-home folder name (English; localization noted) | Phase 3 rung 4 | User-approved design doc §G; proper-casing constraint from interview Q7 |
| [FALLBACK — confirm or override] Codebase-mode workspaces stay plugin-data by default; only topic mode defaults to Documents | Phase 3 mode-split default | DA #2: Documents roots are commonly cloud-synced; codebase lessons embed private-repo snippets — privacy beats visibility for repo-derived state |
| [EXEC-SHAPE] Tier-0 grounding rung + ~1 research dispatch/session cap | Phase 1 ladder | DA #3: /discovery:research is a multi-phase subagent pipeline; per-micro-lesson default cost unacceptable; "never parametric recall" preserved |
| [EXEC-SHAPE] Platform-aware lesson-format default (headless → markdown) | Phase 2 | DA #5: baseline itself chose markdown ("nothing paid for HTML"); HTML is dead weight without a browser |
| [EXEC-SHAPE] git-common-dir worktree slug resolution | Phase 3 | Reviewer #10: per-worktree fragmentation at user-visible roots contradicts the visibility rationale |
| [EXEC-SHAPE] education 0.7.0 minor bump | Phase 7 | Two consumer-visible default changes; changelog-parity gate present in CI |

### User-approval gates

- The [FALLBACK] mode-split default above — confirm or override before Phase 3 lands.
- Phase 3's userConfig key name and the OS-default folder name (`Claude Learning`) are user-visible — flag before Phase 3 lands if you want different naming.
- Any mid-flight discovery that legacy-workspace compat cannot be kept scan-only (i.e. a forced migration) — stop and ask.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Phase order per Brief's impact/value contract with integration-first core (Phase 1) and file-overlap-driven sequencing; Phase 6 slotted anywhere.
- [EXEC-SHAPE] Baseline findings distributed into phases 1–3 where thematically owned, residual sweep in Phase 5.
- [EXEC-SHAPE] Canary mechanism for reload proof: temporary marker string, removed post-verification.

### Mechanical work

One commit per phase minimum, each with its sanity-check evidence in the message; push after every phase (`git push -u origin claude/teach-skill-comparison-h3rpag`); changelog/version bump rides Phase 7; PLAN.md phase tags advanced main-session-only.
