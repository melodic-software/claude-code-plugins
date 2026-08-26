# Plan Review Mode

Spoke for `/planning:plan`. Read this file when the skill is invoked with the `review` argument.

When invoked with `review`:

1. Identify the plan in the current conversation (most recent plan, proposal, or design)
2. Evaluate against the [plan template](plan-template.md). Is anything missing?
3. Check alignment with the consuming project's conventions (its `CLAUDE.md` and rules)
4. Assess whether the blast radius was properly evaluated
5. Present findings: what's strong, what's missing, what needs revision

This is complementary to `/planning:devils-advocate`. Review checks completeness and convention alignment; stress-test checks assumptions and failure modes.
