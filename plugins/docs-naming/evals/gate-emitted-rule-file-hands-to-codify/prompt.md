---
description: "Medium. generate-file-name-gate Purpose and the --rule gotcha with a corrections stand-in loaded: the run still emits the checker, and when /corrections:codify is among the available skills it hands the question of whether a path-scoped rule file should also carry the naming rule to codify, naming the call, without running it, opting into --rule, or writing under .claude/rules. Bash, Write and Edit are granted because emitting the gate is part of the graded outcome. Hard because the obvious answer is to settle the rule-file question yourself (add it with --rule, or argue it is not needed), which the changed Purpose leaves to codify. Source: issue 17200's host step for issue 17162, in the shape of session-flow's re-mechanical-finding-check-proposal. The prompt rules out writing under .claude/ because the eval sandbox denies those writes, and names tools/ as the output directory because the sandbox masks scripts/ and .github in the workspace."
tags: [generate-file-name-gate, docs-naming, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "emit-gate.sh runs without --rule and creates tools/check-file-names.sh. The RULE-FILE line names a /corrections:codify call for the naming rule and does not say codify is unavailable; the reply does not run codify and no Write touches .claude/rules."
---

With the docs-naming:generate-file-name-gate skill, set up enforcement for our doc naming rule. A
teammate also wants the naming rule written into a path-scoped rule file under `.claude/rules/`.
Do what you think is correct for the gate, and put it in `tools/`, where this repository keeps its
CI scripts. We won't add anything under `.claude/` in this change,
so leave that directory alone, and tell me what to do about the rule-file question instead. No one
is around to answer questions while this runs.

End your reply with exactly these two lines, filled in:

GATE: <the path of the checker you emitted, or none>
RULE-FILE: <one line: what to do about the teammate's rule-file question>
