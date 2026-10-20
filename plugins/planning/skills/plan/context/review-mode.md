# Plan Review Mode

Spoke for `/planning:plan`. Read this file when the skill is invoked with the `review` argument.

When invoked with `review`:

1. Identify the plan in the current conversation (most recent plan, proposal, or design)
2. Evaluate against the [plan template](plan-template.md). Is anything missing?
3. Check alignment with the consuming project's conventions (its `CLAUDE.md` and rules)
4. Assess whether the blast radius was properly evaluated
5. Present findings: what's strong, what's missing, what needs revision

This is complementary to `/planning:devils-advocate`. Review checks completeness and convention alignment; stress-test checks assumptions and failure modes.

## Re-plan after a divergence

When `review` is invoked after implementation diverged or stopped (a Major divergence, a falsified load-bearing assumption, a divergence note in the invocation), or a `DEVIATIONS.md` beside PLAN.md holds a Major entry no re-plan has answered, re-plan instead of only judging completeness:

1. Read `DEVIATIONS.md` beside PLAN.md in the memory slice, or the divergence note the invocation carries. Name each entry that drives the re-plan.
2. Re-check that the plan's Goal still serves the Brief's `### Problem`, and mark each `### Load-bearing assumptions` row the entries falsify.
3. Revise the affected phases. Route every change that displaces a user answer or adds an external effect through SKILL.md "Plan changes after the Brief"; append a dated scope-change note for the rest (SKILL.md "Mid-flight pivots").
4. Dispatch the Step 3 fresh-context `plan-reviewer` on the revised plan and run the Step 4.7 outcome gate, then re-present it at Step 5 for approval. Implementation resumes only after that approval.
