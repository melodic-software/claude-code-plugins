# Education quiz-me — post-work comprehension verification

Tracker: melodic-software/claude-code-plugins#799 (contract locked in interview session
`claude-loop-practices`, 2026-07-21; retention seam added in issue follow-up comment).

## Brief

### TLDR

- Add a third sibling skill to the `education` plugin (teach = multi-session coach,
  explain = one-shot altitude drop): after Claude completes a change, generate an HTML
  report of what was done (context, intuition, decisions) with an embedded quiz the user
  answers — verifying the HUMAN absorbed the work, never the artifact.
- Non-gating by default. Opt-in gating via userConfig `quiz_policy:
  off | on-request | always | above-threshold`.
- Quiz/report artifacts are never committed to the product repo: configurable retention
  destination via userConfig, default a local disk library; a companion retrieval flow
  answers "what did we do on ticket X" from that library first, git/ticket archaeology
  second.
- `quiz-me` is the working label, not locked — final name via the codified naming grammar.

### Goal

Failure mode (source: Thariq Shihipar, Anthropic — "Field Guide to Fable" talk + Peter Yang
episode): "people still glaze over the plans and explainers," so the human merging a PR
cannot represent the change to a reviewer and their mental model of the codebase decays,
degrading future prompting. Outcome: a post-work skill that quizzes the user on the
completed work (representation accountability, loop retention, and secondary late
intent-mismatch detection — a failed quiz surfaces "that's not what I intended" pre-merge),
with the report retained as a queryable record (retention-at-write replacing
retrieval-at-need).

### Constraints

- **Object under test is the human, not the artifact.** `verification:confirm` owns
  artifact verification; no overlap. Composition with gate sequences (e.g. session-flow
  workflow) by pointer only — this skill never edits other plugins' gate lists.
- Repo `CLAUDE.md` design rules govern: fresh-docs mandate (WebFetch current skills/plugins
  doc pages before editing, cite URLs), repo-agnostic, plugin-form-safe
  (`${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`), configurable via `userConfig` only.
- `/skill-quality:check` gate passes for every touched skill (listing-budget cap,
  trigger-keyword preservation).
- HTML report + embedded quiz per the canonical prompt pattern (verbatim prompt in
  https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns); markdown
  fallback per project convention.
- Retention: artifacts never land in the consuming repo's tree; destination is a userConfig
  seam with a local disk library default. Same destination-config problem class as #798
  (library_dir portability) — compose, don't fork a second convention.
- Education plugin README currently states the plugin has no `userConfig`; this change
  makes that false — README configuration section must be updated in the same PR.
- PR required; squash merge; Conventional Commits title; branch `feat/799-education-quiz-me`.

### Acceptance criteria

- New skill under `plugins/education/skills/<final-name>/` whose SKILL.md triggers on
  post-work comprehension requests and generates report + quiz per the canonical pattern.
- Default behavior is non-gating (comprehension aid); `quiz_policy` userConfig documented
  with the four values above; `above-threshold` keyed to change size / blast radius.
- Retention destination userConfig with local-library default; generated artifacts land
  there, never in the product repo working tree.
- Retrieval flow exists ("what did we do on ticket X" → retained library first) — shape
  (skill action vs documented query pattern) decided in the plan.
- Boundary documentation: distinction from `/planning:interview` (pre-work, extracts the
  USER's intent — user holds answers) and `verification:confirm` (object = artifact) is
  stated where a consumer would look for it.
- `/skill-quality:check` passes; education plugin version bump + CHANGELOG entry; README
  configuration section updated.

### Captured assumptions

- Primary value is teammate answerability (operator use case: "what did you do on ticket X
  a week ago") — revisit if usage shows the quiz is skipped as ceremony.
- A local disk library (knowledge-corpus as the natural existing home) is an adequate
  retention default — revisit when the Obsidian-vault destination or #798's resolution
  lands.

### Out-of-scope

- Obsidian-vault retention adapter — recorded as a deferred seam (destination userConfig is
  the extension point); do not design now.
- Editing other plugins' gate sequences to insert this skill (pointer-composition only).
- Artifact verification of any kind (`verification:confirm` owns it).

### Deferred questions

- Final skill name via the naming grammar (working label `quiz-me`) — **arbiter: plan**,
  before frontmatter is written.
- `above-threshold` metric definition (diff size? files touched? blast-radius class?) —
  **arbiter: plan**.
- Retrieval-flow shape (dedicated action vs documented library-query pattern) —
  **arbiter: plan**.
- Retention default path and its interplay with #798 `library_dir` indirection — **arbiter:
  plan**, tracking #798's outcome.

## Plan

Standards grounding: repo `CLAUDE.md` (fresh-docs mandate, plugin design rules, branching/PR),
`docs/PLUGIN-PHILOSOPHY.md` (naming grammar §Naming, composition-by-pointer, userConfig
ownership + native-first, version single-home), `docs/MIGRATION-PLAYBOOK.md` (userConfig seam
1, security-review trigger scope, changelog rule). Exploration evidence:
`.work/education-quiz-me/EXPLORE.md` (memory tier). Design sketch:
`design/design-resolution.md`.

### Resolved decisions (Brief "Deferred questions")

1. **Final name: `quiz-me`** — grammar check (`docs/PLUGIN-PHILOSOPHY.md` §Naming):
   imperative verb phrase ✓; `quiz` carries no fixed verb meaning (no collision with
   `audit`/`scan`/`check` semantics — `check-understanding` was rejected precisely because
   `check` means a deterministic pass/fail gate and this skill is non-gating); the `-me`
   qualifier is load-bearing — it names the object under test (the human), the skill's
   defining boundary vs teach's `assess` action and `verification:confirm`. Composes:
   "/education:quiz-me on this change". Rejected: bare `quiz` (under-specifies vs teach's
   in-workspace quizzing), `debrief-me` (loses the test/verification element).
2. **`above-threshold` bar** — the completed change meets ANY of: >5 files touched,
   >200 changed LOC, or the governing plan records blast radius HIGH/CRITICAL. Judged from
   `git diff --stat` at offer time; documented in SKILL.md.
3. **Retrieval flow: `recall` action in the same skill** — action router with two actions:
   default (generate report + quiz for the change just completed) and `recall <query>`
   (answer "what did we do on ticket X" from the retained library first, git/tracker
   archaeology second, stating which source answered).
4. **Retention default: `${CLAUDE_PLUGIN_DATA}`** — artifacts land under
   `${CLAUDE_PLUGIN_DATA}/<repo-slug>/quiz-me/reports/<date>-<change-slug>-<short-hash>.html`.
   `report_library_dir` (type `directory`) userConfig overrides toward a corpus checkout;
   unset = plugin-data default. Guardrail-safe (no machine-specific literal needed),
   zero-config, survives plugin updates; adopts #798's indirection scheme for literal-path
   overrides when that lands.
5. **Library keyed on repo identity, not checkout path** — `<repo-slug>` = repo basename +
   8-hex sha256 of the canonicalized `origin` remote URL (fallback: teach's
   project-path recipe when no remote). Deviates deliberately from teach's
   path-keyed slug: this repo's own workflow runs per-ticket worktrees that are pruned
   after merge, so path-keyed retention would strand every report under a dead slug and
   `recall` from the main clone would find nothing — repo-identity keying makes reports
   from all worktrees land in one library. Side benefit: quiz-me's tree never collides
   with teach's path-keyed slugs in the shared per-plugin `${CLAUDE_PLUGIN_DATA}`; the
   `quiz-me/` path segment adds a second fence.
6. **Answer key persists with the artifact** — the report embeds the key (collapsed
   `<details>` in HTML; appendix section in markdown fallback). Grading is
   in-conversation same-session; a later or compacted session grades by reading the key
   from the retained artifact, re-deriving from report + diff only when the key is
   missing. Without this, the retention use case ("quiz me on ticket X from last week")
   could not be graded at all.
7. **No setup skill** — the userConfig is two optional scalars whose defaults preserve
   zero-config behavior, below PLUGIN-PHILOSOPHY's "non-trivial" bar (knowledge's setup
   skill exists for its external prerequisites, not merely for `library_dir`). Recorded
   so the conformance audit doesn't read silence as a gap.
8. **Offer mechanism is best-effort, no hook** — `always`/`above-threshold` offers are
   model-initiated via description triggers + documented posture, explicitly best-effort
   in SKILL.md. A Stop/skill-scoped hook was evaluated and rejected: it would add a code
   trust surface (re-triggering the acceptance security review) and a kill-switch config
   for a nicety; revisit only if usage shows offers reliably missed. Threshold judged
   against `git diff --stat $(git merge-base HEAD <default-branch>)..HEAD` at offer time
   (well-defined even after commits). `quiz_policy` unknown values fall back to
   `on-request`, documented in the userConfig description (claude-ops precedent).

### Phase 1: SKILL.md authoring [TODO]

Fresh-docs fetch first (repo `CLAUDE.md` mandate): skills page + plugins-reference page;
cite URLs in the PR. Then author `plugins/education/skills/quiz-me/SKILL.md`:

- Frontmatter: `name: quiz-me`; `user-invocable: true`; NO `disable-model-invocation`
  (policy `always`/`above-threshold` requires model-initiated offers; description guards
  triggers). Description ≤1536 chars with single-quoted 'Use when' triggers ('quiz me',
  'do I understand this change', 'what did we do on', 'comprehension check', canonical
  blog phrasing 'quiz at the bottom … that I must pass').
- Body (soft target <200 lines): Purpose (object under test = human; three value props
  from issue); Effective configuration table (`quiz_policy` default `on-request`,
  `report_library_dir` unset → plugin-data; surviving-placeholder-means-unset rule);
  Action router (default = generate, `recall <query>`); Report contract (self-contained
  single-file HTML, inline CSS/JS, no remote fetch, `file://`, synthetic/no secrets —
  teach `context/lessons.md` precedent; markdown fallback; quiz at bottom per canonical
  prompt; answer key embedded collapsed in the artifact per decision 6, grading
  in-conversation same-session or key-read later; failed quiz surfaces possible intent
  mismatch pre-merge); Retention mechanics (repo-identity slug per decision 5, filename
  short-hash, never writes the consuming repo's tree); Non-gating posture + policy
  semantics (best-effort offers, threshold base, unknown-value fallback per decision 8);
  Boundaries ("What this
  skill does NOT do": verification:confirm, planning:interview, teach `assess`/`exercise`
  disambiguation); Gotchas.
- Pointer-composition only: any cross-plugin mention presence-gated ("if installed").

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/education/skills" bash plugins/skill-quality/scripts/check-skill.sh quiz-me` exits 0 (the invocation shape `scripts/check-changed-skills.sh` itself uses); `grep -c '' plugins/education/skills/quiz-me/SKILL.md` < 500.

### Phase 2: Manifest, config, plugin docs [TODO]

- `plugins/education/.claude-plugin/plugin.json`: add `userConfig` (`quiz_policy` string
  default `"on-request"`; `report_library_dir` directory, no default), bump version
  `0.4.0` → `0.5.0`, add keywords (`quiz`, `comprehension`).
- `plugins/education/CHANGELOG.md`: top-insert `## [0.5.0]` `### Added` entry.
- `plugins/education/README.md`: skill list + sibling framing gains quiz-me; Configuration
  section rewritten (drops "no userConfig", documents both keys + defaults); Requirements
  unchanged (no new dependency — reuses declared Bash + coreutils).
- teach and explain SKILL.md stay untouched (trigger-preservation risk; sibling framing
  lives in README — status quo pattern).

**Sanity Check:** `jq -e '.version=="0.5.0" and (.userConfig|has("quiz_policy") and has("report_library_dir"))' plugins/education/.claude-plugin/plugin.json`; `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0 (`--check` alone would pass without the 0.5.0 entry — it only asserts the file exists).

### Phase 3: Evals [TODO]

`plugins/education/skills/quiz-me/evals/evals.json` (`skill_name: quiz-me`, sibling
schema shape), ~6 evals: canonical-prompt trigger produces report+quiz; default policy is
non-gating (no unsolicited block); `quiz_policy: off` respected; artifact never written to
repo tree; `recall` queries library before git archaeology; boundary handoff (artifact
verification request routes to verification:confirm, not quizzed).

**Sanity Check:** validate `plugins/education/skills/quiz-me/evals/evals.json` against `plugins/skill-quality/reference/evals.schema.json` with one of the validators `skill-quality:check` itself accepts — `check-jsonschema` (Python/pipx), `ajv`, or `python -m jsonschema` — exit 0 (check-jsonschema is NOT an npm package; `npx` cannot run it).

### Phase 4: Catalog + marketplace [TODO]

- `node scripts/generate-catalog.mjs` — regenerate root `README.md` catalog block.
- `.claude-plugin/marketplace.json`: add `quiz` / `comprehension` to the education entry's
  `tags` (discovery-tag change; the explain exemplar did the same).

**Sanity Check:** after editing marketplace tags, run `node scripts/generate-catalog.mjs` then `git diff --exit-code README.md` exits 0 (catalog is a committed regeneration, not drift); `jq -e '.plugins[]|select(.name=="education").tags|index("quiz")' .claude-plugin/marketplace.json` exits 0.

### Phase 5: Gate sweep [TODO]

Run the CI-mirroring local gates over the diff: `scripts/check-changed-skills.sh origin/main`,
`scripts/check-skill-leaf-names.sh --check` (register `quiz-me` if a cross-plugin
collision is reported — none known), `scripts/check-skill-portability.sh`, markdownlint
(`npx --no-install markdownlint-cli2`), `scripts/validate-plugins.sh`.

**Sanity Check:** every listed script exits 0.

## Blast radius

LOW — additive prompt-only skill inside one plugin; no cross-plugin edits, no hooks, no
scripts, no network, no new trust surface (no security-review re-trigger per
`docs/MIGRATION-PLAYBOOK.md`); worst regression is a bad new skill that consumers simply
don't invoke, plus a README/manifest documentation error.

## Stress-test summary

Fresh-context plan reviewer (Step 3): 1 CRITICAL + 6 IMPORTANT + 4 SUGGESTION, all
verified and folded in — corrected the check-skill.sh invocation (needs
`CHECK_SKILL_SKILLS_ROOT`), changelog gate (`--check-bump origin/main`), evals validator
(check-jsonschema is Python, not npm); resolved the worktree-pruned-slug retention trap
(decision 5), later-session answer-key grading (decision 6), setup-skill silence
(decision 7), best-effort offer semantics + threshold diff base + unknown-value fallback
(decision 8), plugin-data coexistence with teach and filename collisions (decisions 4-5).
Formal `/devils-advocate` skipped: blast radius LOW, no trigger matched.

## Execution shape

Fully sequential, single implementation lane — all five phases write inside
`plugins/education/` + two root catalog files; file overlap and the version/CHANGELOG
coupling make parallel waves pointless. Routing: one scope-fenced implementation subagent
executes Phases 1–5 (orchestrator never edits source, per the work-items dispatch
posture); main session verifies returns and owns PLAN.md updates.

## Open questions

None blocking; user-overridable decisions listed under "Decisions made" in the approval
presentation.

## Handoff to implementation

### User-approval gates

- Plan approval itself (pending — presented at end of planning session).
- Skill NAME `quiz-me` — hard to reverse post-publish (rename sweep); flagged for explicit
  confirmation at plan approval.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential single-worker dispatch; worker ALLOWED:
  `plugins/education/**`, `README.md` (regen only), `.claude-plugin/marketplace.json`
  (tags only). FORBIDDEN: everything else, `docs/topics/**` (PLAN.md is
  main-session-owned), other plugins.
- [EXEC-SHAPE] Omit `disable-model-invocation` on quiz-me (policy-driven offers need
  model invocation; explain precedent).
- [EXEC-SHAPE] teach/explain SKILL.md untouched; sibling framing via README only.
- [EXEC-SHAPE] `above-threshold` numbers (>5 files / >200 LOC / blast ≥ HIGH).
- [FALLBACK — confirm or override] If #798's indirection scheme lands mid-implementation,
  adopt it for `report_library_dir` literal-path overrides; otherwise document literal
  paths as guardrail-constrained (same caveat knowledge README carries).

### Mechanical work

Commit per phase or logical pair (Conventional Commits, `feat(education): …` PR title);
squash merge; PR body: `Closes #799`, `## Related` (#798, knowledge-corpus digest PR 3),
attribution trailer + session link; PLAN.md phase tags advance with each phase's commit;
close-out (PR time): paste PLAN.md into PR `<details>`, prune `docs/topics/education-quiz-me/`
before merge per /planning:plan close-out.
