---
description: "Legacy check eval 10. /skill-quality:check measure-invocation probes over a scaffolded 16-query probe set for a fixture skill (skill_dir is the absolute SKILL.md path, so it resolves whether or not the staged plugin sits in a git repository). The listing-overlap floor scores train trigger_rate 1, false_trigger_rate 0.25 and validation trigger_rate 0.75, false_trigger_rate 0 (scored offline with the bundled script). check SKILL.md Action: measure-invocation: run validate then score, report trigger_rate and false_trigger_rate per split, say listing-overlap is a floor, not a model-graded rate; it rewrites no description. ran-score (indicator) grades the score call; no-contract-gate grades that the static contract gate (check-skill.sh) is not run; train-false-trigger and validation-trigger grade the two numbers only the run produces, each beside its split; names-both-rates grades the false-trigger rate named; names-floor grades the floor caveat; no-edit and no-write grade that no description is rewritten. The prompt names ./probes in the working directory: smoke 1's bare 'probes' was read as the plugin's own seed probes, which do not resolve in a workspace, so score exited 2. Needs --scaffold --allow-tools Bash."
tags: [skill-quality, check, measure-invocation, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply runs the probe harness on ./probes and reports, for fixture:release-notes, train trigger_rate 1 and false_trigger_rate 0.25, validation trigger_rate 0.75 and false_trigger_rate 0; says listing-overlap is a lexical floor, not a live auto-invocation rate; and changes no skill description."
---

/skill-quality:check measure-invocation ./probes

./probes is the probe set in the current working directory.
