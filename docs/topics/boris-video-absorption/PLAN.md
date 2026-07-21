# PLAN — boris-video-absorption

## Brief

Absorb the vetted ideas from the Ray Amjad "4 Levels of Agentic Coding"
video digest (research base:
`~/.work/youtube-watch/the-4-levels-of-agentic-coding-how-to-sh-XLA-sTSJ-Wc/`)
into the plugin estate. Interview-locked contracts (this session):

- Extend existing seams, no new skill: `testing:run-e2e` (driver) +
  `verification:confirm` (judge) keep their division of labor.
- run-e2e gains: subagent-isolated surface runs; native-/verify-first
  delegation (presence-gated, CC ≥2.1.145); structured missing-environment
  gap report on prerequisite failure (hard-fail stays, plus actionable
  report); video/session-artifact evidence tier.
- Recording format (video | gif | off) and browser mode (headed |
  headless) are layered config knobs per
  `docs/conventions/consumer-config-layering/` — NOT hardcodes.
- `plugins/autonomy/reference/routines.md` gains a thin-pointer clause:
  routine/scheduled-task prompts on any surface point to
  version-controlled files; pasted prose non-compliant.
- `~/.claude/scheduled-tasks/` (exists, live task) proposed for dotfiles
  tracking via the dotfiles repo's add-dotfile flow.
- Deferred-with-trigger (recorded in digest slice, NO tracker issues):
  verification self-improvement loop (trigger: accumulated recorded
  runs); bounded build→review→fix loop (trigger: post-Phase-II
  enforcement rail); Claude Tag enablement (trigger: post-8/3 cutover +
  Enterprise admin check).
- Out of scope: presenter-custom harness (Percy), chat-surface wiring,
  Chronicle adoption, lifecycle reordering.
- Boris doc capture re-verified NO-DRIFT 2026-07-21; all adopted items
  trace to the doc's step 1→2/2→3 recipes or native CC features.

Success: PRs merged with skill-quality + markdownlint green; every
adopted behavior traceable to research findings; zero collision with the
primary session's lanes (ignition Phases 2–3 merged via #810; no pending
branch touches target files — verified).

## Standards grounding

- `docs/conventions/consumer-config-layering/README.md` — three layers
  (user-global / team / local overlay), additive-preferred merge; new
  config surface must declare keys in the owning plugin's docs and point
  at the convention for layering.
- `docs/CATALOG-TAXONOMY.md` + `docs/PLUGIN-PHILOSOPHY.md` — extend-over-
  add, seam cooperation presence-gated, fresh-eyes delegation.
- Repo commit/PR conventions (conventional commits, codex thread
  resolution before merge, `--body-file -` for PR bodies).

## Plan

### Phase 1: Lane setup [DONE]

- Create worktree off `origin/main`, branch `feat/boris-video-absorption`
  (sibling-worktree convention).
- Materialize `docs/topics/boris-video-absorption/PLAN.md` (this file) +
  `design/design-resolution.md` (Tier B early-exit: no new types; one new
  config surface whose shape is resolved here — see Decisions).
- Post coordination comment on #778: secondary session lane, files
  touched, no overlap with ignition/enforcement lanes.
- **Sanity Check:** `git worktree list` shows the new worktree on the new
  branch; `gh issue view 778` shows the comment; PLAN.md exists in the
  worktree at `docs/topics/boris-video-absorption/PLAN.md`.

### Phase 2: run-e2e enrichment [TODO]

Files: `plugins/testing/skills/run-e2e/SKILL.md`,
`plugins/testing/skills/run-e2e/context/e2e.md`,
`plugins/testing/README.md`, new
`plugins/testing/skills/run-e2e/context/e2e-config.md` (key owner doc),
`plugins/testing/skills/run-e2e/evals/evals.json` (eval #1 asserts the
prerequisite-failure behavior this phase changes — update
unconditionally), `plugins/testing/CHANGELOG.md` (Keep a Changelog entry;
**minor** bump — new behaviors),
`docs/conventions/consumer-config-layering/README.md` (Implementers-table
row for the new surface — the convention tracks conformance, not
assumes it).

- Declare config surface `.claude/testing/e2e.md` (folder-form name per
  convention: surface identity = whole path relative to `.claude/`).
  Keys: `recording: video | gif | off` (default `off` — evidence contract
  screenshots stay the floor), `browser_mode: headed | headless` (default
  headless, operator overrides for visibility). Per-key override
  semantics. Layering resolution cites the convention doc — no
  restatement.
- **Read path (reviewer gap #3 — mandatory):** SKILL.md gains explicit
  resolution instructions — anchor at repo root, read all three layers
  (user-global → team → local overlay), merge per-key, report which layer
  supplied each effective value. **Plumbing:** resolved `browser_mode`
  and `recording` are passed to the executor (`/playwright:playwright`
  invocation args / gif_creator choice) — keys without plumbing are the
  documented ai-briefing deviation; not repeating it.
- **Key-ownership framing (reviewer risk #6):** e2e-config.md states the
  boundary — run-e2e owns capture POLICY (what evidence, which format,
  visibility preference); playwright owns MECHANICS (how the browser
  runs). Keys are policy inputs run-e2e resolves and passes through.
- **Precedence (operator-locked):** config keys are DEFAULTS only; an
  explicit session prompt always wins ("run this headed" overrides
  `browser_mode: headless`). e2e-config.md states this: prompt >
  local overlay > team > user-global > bundled default.
- SKILL.md: subagent-isolated run guidance (delegate the drive loop to a
  subagent; orchestrator consumes evidence paths only); /verify-first
  delegation note (presence-gated on bundled /verify, CC ≥2.1.145, with
  existing orchestrator fallback unchanged).
- Prerequisite failure path: keep hard-fail STOP; add a structured
  verification-environment gap report (what's missing, what the operator
  must provide — keys/CLIs/environments; the "what do you need to verify
  this e2e" elicitation) written to the run's evidence output.
- context/e2e.md evidence contract: add optional recording tier (video
  via playwright CLI preferred for long flows; GIF via gif_creator for
  short demos — driven by the `recording` key) + session artifacts row
  (recording path, session ID, transcript pointer) in the evidence table.
- **Sanity Check:**
  `rg -c "e2e-config|\.claude/testing/e2e\.md" plugins/testing/skills/run-e2e/SKILL.md`
  ≥ 1; `rg -c "gap report" plugins/testing/skills/run-e2e/SKILL.md` ≥ 1;
  `rg -c "recording" plugins/testing/skills/run-e2e/context/e2e.md` ≥ 2;
  **read-path present:**
  `rg -c "layer" plugins/testing/skills/run-e2e/SKILL.md` ≥ 2 AND
  `rg -c "browser_mode" plugins/testing/skills/run-e2e/SKILL.md` ≥ 2
  (resolution + plumbing sites); Implementers-table row:
  `rg -c "testing/e2e" docs/conventions/consumer-config-layering/README.md`
  ≥ 1; CHANGELOG entry present; eval #1 updated
  (`rg -c "gap" plugins/testing/skills/run-e2e/evals/evals.json` ≥ 1);
  markdownlint exit 0 on changed files; `/skill-quality:check run-e2e`
  PASS.

### Phase 3: confirm delegation touch-up [TODO]

Files: `plugins/verification/skills/confirm/SKILL.md`,
`plugins/verification/README.md` (only if wording drifts),
`plugins/verification/CHANGELOG.md` (**patch** bump — wording touch-up).

- Delegation section: acknowledge enriched run-e2e (subagent isolation +
  recording/session evidence tier + gap report); /verify stays named as
  the supplementary live-run path with unchanged presence gate. No
  structural change to stages or verdict machinery.
- **Sanity Check:**
  `rg -c "gap report|recording" plugins/verification/skills/confirm/SKILL.md`
  ≥ 1; stage structure unchanged
  (`rg -c "Stage" plugins/verification/skills/confirm/SKILL.md` equal
  before/after); markdownlint exit 0.

### Phase 4: routines.md thin-pointer clause [TODO]

Files: `plugins/autonomy/reference/routines.md`,
`plugins/autonomy/CHANGELOG.md` (**minor** bump — new normative clause).

- New subsection, phrased to honor the doc's hosting-agnosticism
  (reviewer risk #7): the NORMATIVE clause is surface-agnostic — "a
  routine's instruction content lives in a version-controlled, reviewable
  artifact; the stored prompt is a thin pointer to it; pasted-prose
  prompts are non-compliant (no history, invisible drift)". The
  surface-specific mappings (cloud routines → committed
  `.claude/skills/`, documented transfer path; Desktop scheduled tasks →
  `~/.claude/scheduled-tasks/<task>/SKILL.md` under dotfiles) appear only
  as ILLUSTRATIVE binding examples, marked as deployment-owned bindings
  per the doc's own Hosting stance. Cite research
  (`routines-versioning-deep-dive.md`: native prompt versioning
  documented-absent). If the clause reads better in
  `wiring-vs-advisor.md` at build time, the builder flags it back to the
  main thread rather than deciding — placement objection is the known
  review risk.
- **Sanity Check:**
  `rg -c "thin pointer|version-controlled" plugins/autonomy/reference/routines.md`
  ≥ 2; agnosticism preserved:
  `rg -c "deployment-owned" plugins/autonomy/reference/routines.md`
  count increases by ≥1; markdownlint exit 0; CHANGELOG entry present.

### Phase 5: digest-slice deferred items + through-line [TODO]

Files (home slice, not repo):
`~/.work/youtube-watch/the-4-levels-of-agentic-coding-how-to-sh-XLA-sTSJ-Wc/recommendations/menu.md`,
`README.md` (same slice).

- Update menu items to final dispositions (adopted → PR refs; deferred →
  named triggers; no-go unchanged). Add through-line note: Boris doc →
  interview locks → PLAN → PRs.
- **Sanity Check:** `rg -c "deferred" menu.md` ≥ 3; each adopted item
  carries a PR/branch reference.

### Phase 6: dotfiles tracking proposal [TODO — user gate]

- Run the dotfiles repo's `add-dotfile` flow for
  `~/.claude/scheduled-tasks/` (dir exists with live
  `autonomy-demo-hourly-drain/`). Flow owns chezmoi mechanics; never
  `chezmoi apply` from agent context.
- **Sanity Check:** dotfiles repo PR/branch exists containing the
  scheduled-tasks source state, or an explicit operator decline recorded
  in PLAN.
- **User gate:** surfaces before executing (cross-repo write).

### Phase 7: verify + ship [TODO]

- Empirical verification in worktree: markdownlint sweep, typos gate,
  `/skill-quality:check` per touched skill, eval validation.
- Version bumps via Edit on the version line (biome retab gotcha).
- Conventional commits; PR(s) with PLAN.md in `<details>`; codex threads
  resolved before merge; close-out per `/planning:plan close-out`
  (slice prune + pointer).
- **Sanity Check:** CI green on PR; `gh pr view` shows mergeable; all
  phase tags [DONE].

### Phase 8: trial run (post-merge validation) [TODO]

- After plugins update, run the enriched flow end-to-end on a real UI
  change in a consumer repo: config surface resolved + reported,
  recording produced per key, gap report exercised (remove a prereq
  deliberately), evidence table carries session artifacts.
- **Sanity Check:** recording artifact exists on disk; gap report emitted
  on induced prereq failure; operator reviews the recording.

## Blast radius

LOW-MEDIUM. Markdown skill/contract text + one new additive config
surface; zero runtime code; three plugins touched; consumers unaffected
by default (recording defaults off, browser_mode default preserves
current behavior). Cross-repo edge: dotfiles proposal (user-gated).

## Stress-test summary

Fresh-context plan-reviewer ran against live repo. 3 CONFIRMED-GAPs
folded: (1) phantom config surface — read-path resolution + executor
plumbing now mandated in P2 with sanity greps; (2) Implementers-table
row added to P2 files; (3) CHANGELOG entries added to P2/P3/P4 with
SemVer magnitudes (testing minor, verification patch, autonomy minor).
Risks addressed: key-ownership boundary framed policy-vs-mechanics in
e2e-config.md; routines.md clause re-phrased surface-agnostic with
bindings as illustrative examples; eval #1 update made unconditional.
Collision re-verified clean (no open PR overlap). Formal
/devils-advocate skipped: blast radius LOW-MEDIUM, no
infra/CI/dependency triggers.

## Execution shape

Wave A (parallel, file-disjoint, one worktree, agents never touch git):

| Phase | Surface | Basis |
|---|---|---|
| 2 run-e2e | Opus builder subagent | mechanical doc edits, largest item |
| 3 confirm | Opus builder subagent | small disjoint edit |
| 4 routines | Opus builder subagent | small disjoint edit |

Wave B (sequential, main thread): 5 (home slice), 6 (user-gated
cross-repo), 7 (verify + ship — main thread only, empirical checks +
git).

Phase 1 precedes all. Scope fences: each builder gets an ALLOWED list =
its phase's files; FORBIDDEN = PLAN.md, other phases' files, any git
command. Cost: 3 builders vs sequential saves modest wall-clock; fallback
= run 2→3→4 sequentially in main thread on any fence violation.

## Open questions

None blocking — all interview-locked.

## Handoff to implementation

### User-approval gates

- Phase 6 dotfiles add-dotfile run (cross-repo write).
- Any mid-flight scope change to config-surface shape.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] PLAN drafted in `.work/` first; materialized to
  `docs/topics/` inside the worktree at Phase 1 (avoids writing to the
  canonical checkout the primary session owns).
- [EXEC-SHAPE] Wave A 3-builder parallel shape with scope fences as
  above; sequential fallback documented.
- [EXEC-SHAPE] Single PR for phases 2–4 (one review surface, shared
  rationale) unless review load argues for a split at ship time.

### Mechanical work

- Commit boundaries: Phase 1 (PLAN + design-resolution), one commit per
  phase 2–4, Phase 5 lives outside the repo (no commit), Phase 7 ship.
- Verification checkpoints: markdownlint + typos + skill-quality per
  phase before its commit; empirical greps per Sanity Checks.
- Sequential fallback: any fence violation → abandon parallel, re-run
  remaining phases in main thread.
