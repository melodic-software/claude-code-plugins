# /planning:plan Checklist

Copy into `<memory_dir>/<topic-slug>/plan-checklist.md` (default `.work/`; the topic's memory slice). Tick as each step completes.

## Steps

- [x] Step 1: Prerequisite check. Brief locked (PLAN.md Brief section exists OR equivalent crisp framing); exploration + research done or explicitly waived; design gate evaluated
- [x] Step 2: Formulate the plan. Phases with verifiable Sanity Checks per phase; estimate scope; identify parallelism
- [x] Step 3: Plan stress-test (MANDATORY, never skip). Dispatch a fresh-context plan-reviewer sub-agent per context/plan-reviewer.md
      Run: fourteen findings, two blockers (acceptance criteria 1 and 3 mapped to no phase; unpinned release provisioning). All folded in except two whose own citations did not hold, corrected in the Stress-test summary.
- [x] Step 3b: Assess blast radius (LOW / MEDIUM / HIGH / CRITICAL). This gates whether Step 4 runs
      MEDIUM: new plugin and marketplace surface, isolated by `defaultEnabled: false` and no hooks, but apply/remove write into game folders. MEDIUM triggers Step 4.
- [x] Step 4: Formal stress-test + research-iterate (CONDITIONAL on Step 3b ≥ MEDIUM). Invoke `/planning:devils-advocate` and targeted research on contested claims
      Run: twenty-three findings, six CRITICAL/HIGH reshaped the plan (model-side path resolution, game-root anti-cheat scan, apply rollback, GameKey collisions, state orphaning, byproduct single source). Contested release metadata and gate-script paths re-verified against `gh api` and `.github/workflows/ci.yml`.
- [ ] Step 4.5: Execution-shape analysis (default ON for multi-phase plans). Emit scope-fencing tables + per-phase routing table
- [ ] Step 4.6: Tag unilateral decisions. Flag any choice made without explicit user approval; interview below-bar decisions
- [ ] Step 4.7: Outcome gate. Binary checks read off the PLAN artifact (sanity-check count, phase tags, scope mapping, decisions table, blast-radius line)
- [ ] Step 5: Present for approval. Persist PLAN.md; wait for the user gate before any code edits

## Skip criteria

- Step 3 NEVER skipped (mandatory: stress-test before presenting)
- Step 4 SKIPPED when Step 3b verdict = LOW blast radius and no trigger matches
- Step 4.5 SKIPPED when the plan is single-phase (no parallelism axis, all-main-session default)
- Step 4.6 SKIPPED when no unilateral decisions were made (user approved every choice during Q&A)

## How to use

Copy at session start; tick boxes as steps complete; a resuming session reads the unticked boxes to know where to continue.

## Step 1 evidence

Brief locked from the handoff `.work/handoffs/20260921T045656Z-handoff-dlss5-plugin.md` sections
"Original goal" and "Completion criteria". Exploration and research were completed in the
producing session and persist under `.work/dlss5/research/`. Design gate evaluated: early exit
recorded at `docs/topics/dlss5-plugin/design/design-resolution.md`, tier B.
