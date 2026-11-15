---
description: "Planning a change that reshapes an existing module nobody scanned: the prerequisite check's list of other skills that apply names /architecture:improve, and no plan is written yet"
tags: [plan, prerequisites, architecture, composition, scaffold, no-network]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "The reply reports the prerequisite check for the split-invoicing Brief and, among the other skills that apply, names /architecture:improve for the existing modules being reshaped. It stops before writing the plan"
---

/planning:plan

Topic slug `split-invoicing`; the Brief is in `.work/split-invoicing/PLAN.md`. Run only the prerequisite check for now: tell me what it found and which other skills apply to this task before planning, then stop. Don't write the plan yet.
