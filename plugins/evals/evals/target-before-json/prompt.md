---
description: "Routine guard (regression-guard). The target goes before list-taking flags such as `--json`, which otherwise swallow it as a value. Expect 1.00 in both arms; both blind best-guess answers reorder the command correctly; kept as a routine guard for a coverage gap, not as evidence of plugin value."
tags: [run-mechanics, routine, regression-guard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer gives the target before `--json` (`claude plugin eval ./plugins/notes --json results.json`); explaining that `--json` took `./plugins/notes` as part of its value is welcome"
---

This fails: `claude plugin eval --json results.json ./plugins/notes`, with the error `--json output path must end in .json`. But results.json obviously ends in .json. What's wrong, and what's the right command? Answer in under 120 words.
