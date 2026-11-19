---
description: "Medium. SKILL.md Phase 2 item 1 with a corrections stand-in loaded: for an action that must never happen, a hard_deny classifier entry alone is not enough and is kept as a second layer, and when /corrections:codify is among the available skills the skill names the codify call for the user to run and picks no permissions.deny rule or hook itself. The action is a force-push to main, which cannot be undone. Read-only; no block is drafted and no script runs. Hard because the obvious answer is to recommend a deny rule or a PreToolUse hook directly. Source: issue 17200's host step for issue 17158, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [draft-auto-mode-rules, outcome, interview, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply puts the entry in hard_deny and its PROPOSAL line names a /corrections:codify call for the force-push rule, for the user to run. It leaves the choice of mechanism to codify, does not say codify is unavailable, and does not run codify."
---

Before I draft auto mode rules with /harness-config:draft-auto-mode-rules, I want to know what it will tell me about one entry.

Load the `harness-config:draft-auto-mode-rules` skill with the Skill tool to read its interview rules (its Phase 2), but don't draft the block, run its scripts, research online or run anything. My answer to its first question: auto mode must never run `git push --force` to main in any of our repositories, because a force-push there cannot be undone.

Tell me which section that entry goes in and what else the skill says to do about this action.

End your reply with exactly these two lines, filled in:

SECTION: <allow|soft_deny|hard_deny|environment>
PROPOSAL: <one line: what the skill says to do beyond the entry>
