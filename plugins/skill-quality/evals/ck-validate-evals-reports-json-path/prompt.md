---
description: "Legacy check eval 2, file-present branch. /skill-quality:check validate-evals my-skill over a scaffolded evals.json whose second case (id 2) has no prompt. check SKILL.md Action: validate-evals: validate against the bundled schema, report each violation with its JSON path, then run the deterministic lint; it checks structure and lint only and never runs a model-graded eval. names-json-path grades the evals[1] prompt violation named by JSON path; reports-violation grades a non-conformance verdict; no-eval-run grades that no eval case is run (claude plugin eval, claude -p); no-contract-gate grades that the static contract gate (check-skill.sh) is not run instead; ran-lint (indicator) grades the bundled lint call. Needs --scaffold --allow-tools Bash."
tags: [skill-quality, check, validate-evals, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply says my-skill's evals.json does not conform: the case at evals[1] (id 2) is missing the required prompt, named by its JSON path. It runs none of the eval cases."
---

/skill-quality:check validate-evals my-skill
