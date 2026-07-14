# /architect Checklist

Copy into `.work/<topic-slug>/architect-checklist.md` (the topic's memory slice). Tick as each step completes.

## Steps

- [ ] Step 1: Prerequisite check — Brief locked (PLAN.md Brief section exists OR equivalent crisp framing); exploration + research done or explicitly waived; design gate evaluated
- [ ] Step 2: Formulate the plan — phases with verifiable Sanity Checks per phase; estimate scope; identify parallelism
- [ ] Step 3: Plan stress-test (MANDATORY — never skip) — dispatch a fresh-context plan-reviewer sub-agent per context/plan-reviewer.md
- [ ] Step 3b: Assess blast radius (LOW / MEDIUM / HIGH / CRITICAL) — gates whether Step 4 runs
- [ ] Step 4: Formal stress-test + research-iterate (CONDITIONAL on Step 3b ≥ MEDIUM) — invoke `/devils-advocate` and targeted research on contested claims
- [ ] Step 4.5: Execution-shape analysis (default ON for multi-phase plans) — emit scope-fencing tables + per-phase routing table
- [ ] Step 4.6: Tag unilateral decisions — flag any choice made without explicit user approval; interview below-bar decisions
- [ ] Step 4.7: Outcome gate — binary checks read off the PLAN artifact (sanity-check count, phase tags, scope mapping, decisions table, blast-radius line)
- [ ] Step 5: Present for approval — persist PLAN.md; wait for the user gate before any code edits

## Skip criteria

- Step 3 NEVER skipped (mandatory — stress-test before presenting)
- Step 4 SKIPPED when Step 3b verdict = LOW blast radius and no trigger matches
- Step 4.5 SKIPPED when the plan is single-phase (no parallelism axis — all-main-session default)
- Step 4.6 SKIPPED when no unilateral decisions were made (user approved every choice during Q&A)

## How to use

Copy at session start; tick boxes as steps complete; a resuming session reads the unticked boxes to know where to continue.
