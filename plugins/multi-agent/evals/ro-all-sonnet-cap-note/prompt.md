---
description: "Legacy route 5, natural language with session=sonnet stated literally. route SKILL.md lines 41-58 and 114-115: the JSON is printed unchanged (verifier effort high), the hard-cap line follows the per-role lines verbatim, and route reads no settings file; the cap applies at run time. says-runs-at-medium needs a run-time verb with medium, which the prompt lacks. The settings-read graders cover Read, Grep, Glob and any Bash command naming a settings file; a read of the run's own home settings may also be denied and read INVALID. Writes are not granted. invoked-route and ran-route-all-sonnet are with-only indicators. Needs --allow-tools Bash."
tags: [multi-agent, route, outcome, effort-cap, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh all session=sonnet runs; the fenced JSON keeps the verifier at effort high, the line Effort above maxEffortLevel runs at the cap; see reference/config.md \"Hard cap\". comes after the per-role lines, the reply says the higher efforts run at medium under the cap, and no settings file is read."
---

Route all roles for a workflow; my managed settings set maxEffortLevel to medium. This session is Sonnet (session=sonnet).
