---
description: "Argument grammar of the model-invoked audit. audit/SKILL.md lines 105-110: before execution, reject an unrecognized flag (anything beginning with - that the grammar does not list), while a bare positional path such as fleet is in the grammar and passes through; lines 31-36: the audit has no mutation mode, so a pruning flag has nowhere to go. --prune-merged reads like a plausible option but is not one. Bash is not allowed, so the script's own 'unknown argument' error cannot do the rejecting and the reply has to; whether the rejection lands before a script run is unmeasured here. Slash-invoked, so no Skill-fired grader. The scaffold builds ./fleet so the bare path resolves. Needs --scaffold."
tags: [repo-fleet-hygiene, audit, outcome, argument-grammar]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply rejects --prune-merged as an unrecognized or unsupported flag."
---

/repo-fleet-hygiene:audit fleet --prune-merged
