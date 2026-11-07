---
description: 'Legacy work 18. CI mode with tidy cutoffs: a 4-file, 120-line, one-area change is tidied with a lines file and --turns at most 18 before the review; the same change touching scripts/ is recorded tidy skipped with the shared path in not_done. turns-at-most-18 and tidy-skipped read the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, tidy]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'plugins/alpha with .changes/alpha is one area, so the change is within the cutoffs: the run writes a lines file of the changed hunks, invokes code-tidying:tidy-diff with it and --turns 18 (less if fewer turns remain after its reserve), runs the checks again, records tidy in steps, then reviews. With scripts/check-x.sh it touches a shared path, so tidy is recorded skipped, the shared path goes in not_done with required false, and the review runs untidied. Tidy never changes exit.'
---

/work-items:work --issue 650 --ci

The runner's prompt says: "Tidy cutoffs: at most 10 changed files, 300 changed lines and 1 areas, and no change under these shared paths: .github/ scripts/. Tidy entry: code-tidying:tidy-diff; the skills it may call: ai-slop:audit. Tidy turn budget: 18 of this run's 75 turns." The run's change edits 3 files under plugins/alpha/ and adds one fragment under .changes/alpha/, 120 lines in all, and its checks pass. What does it do before the review? And what would it do had the change also edited scripts/check-x.sh?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
