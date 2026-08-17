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

(To be filled by /planning:plan.)
