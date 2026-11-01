---
description: "Routine guard (regression-guard). The target goes before list-taking flags such as `--allow-tools`, which otherwise swallow it as a value, leaving the CLI with no target. Kept as a routine guard for a coverage gap, not as evidence of plugin value."
tags: [run-mechanics, routine, regression-guard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer gives the target before `--allow-tools` (`claude plugin eval ./plugins/notes --allow-tools Write Edit`); explaining that `--allow-tools` took `./plugins/notes` as one of its values is welcome"
---

I only wanted my notes plugin's evals, but this started loading every eval suite in my repo: `claude plugin eval --allow-tools Write Edit ./plugins/notes`. What's wrong, and what's the right command? Answer in under 120 words.
