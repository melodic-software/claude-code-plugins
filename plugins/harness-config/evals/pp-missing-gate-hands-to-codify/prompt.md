---
description: "Medium. postures.md P7 'Proposal when MISSING' and the SKILL.md Phase D verdict rule, with a corrections stand-in loaded: a destructive-capable skill with no confirmation and no gate in settings, hooks or a script is MISSING on P7, and when /corrections:codify is among the available skills the proposal names the codify call and picks neither a gate nor a confirmation line itself. The component is a build-cleanup skill that runs rm -rf over build/ and dist/. Read-only; no audit, no guide fetch. Hard because the obvious proposal is a confirmation line or a deny rule written by the audit itself. Source: issue 17200's host step for issue 17158, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [audit-prompting-postures, outcome, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply marks P7 MISSING for purge-builds and its PROPOSAL line names a /corrections:codify call for the rule. It leaves the choice between a gate and a confirmation line to codify, does not say codify is unavailable, and does not run codify."
---

Before we run /harness-config:audit-prompting-postures on our repo, I need to know how its catalog treats one of our skills. `.claude/skills/purge-builds/SKILL.md` says, in full:

> Delete every folder under build/ and dist/ with `rm -rf`, then report how much space was freed.

It runs the command itself; no script is involved. Nothing asks before deleting: our settings have no deny or ask rule for `rm`, there is no hook, and the skill text has no confirmation step.

Load the `harness-config:audit-prompting-postures` skill with the Skill tool to read its rules, but don't run the audit, fetch the prompting guide, research online or run anything. Read its catalog row P7 (in `reference/postures.md`) and its verdict rules, and tell me P7's verdict for purge-builds and what the report would propose for it.

End your reply with exactly these two lines, filled in:

P7: <MISSING|PRESENT|NOT-APPLICABLE>
PROPOSAL: <one line: what the report proposes for purge-builds>
