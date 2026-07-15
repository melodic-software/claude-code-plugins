# /interview Checklist

Copy into `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; the topic's memory slice). Tick as each step completes.

## Steps

- [ ] Step 1: Survey before you ask — read existing context, the topic's contract and memory slices, conversation history; identify what's already settled
- [ ] Step 1.5: Auto-detect (default action only) — if intent already crisp from survey, route to direct synthesis (skip Q&A loop)
- [ ] Step 2: Drive the depth-first loop — one question at a time, **inline prose** (the one-at-a-time loop never uses `AskUserQuestion`; `lock` synthesizes without Q&A); resolve load-bearing first; restate decided/open after each answer
- [ ] Step 3: Recognize the stop condition — remaining-open is empty OR user signals "good, proceed"
- [ ] Step 4: Persist the contract — engineering: write the PLAN.md Brief section with goal + constraints + acceptance criteria + captured assumptions; general: write the shared-understanding summary, never a Brief (`me` mode: persist each answer incrementally as it locks in; flush before context overflows)
- [ ] Step 5: Hand off — engineering: recommend the next skill (exploration/research for engineering-internal; chain after `/prd` for product-driven); general: deliver the summary and stop, no pipeline handoff

## Decision tree (`me` mode only)

Relentless `me` mode expands Step 2 into one checkbox per branch (not a single step box). Maintain in `interview-checklist.md`; tick on resolve; loop until zero open consequential branches:

- [ ] <branch 1> — <decision once resolved>
- [ ] <branch 2> (blocked by: <branch>)
- [ ] <branch N>

No question cap. If branches outgrow the session, hand off (save-point + resume prompt) → clear → resume from the first open box.

## Skip criteria

- Step 2 SKIPPED when Step 1.5 auto-detect routes to direct synthesis
- Step 1.5 SKIPPED when user explicit-mode (`lock` forces synthesis; `me` forces Q&A loop)

## How to use

Copy at session start; tick boxes as steps complete; a resuming session reads the unticked boxes to know where to continue.
