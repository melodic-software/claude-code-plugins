---
description: "Scaffold: the workspace's .claude/settings.json sets disableWorkflows true, a switch workflow-availability.sh reports as off; the CLAUDE_CODE_DISABLE_WORKFLOWS variable of legacy assess 2 cannot reach a run, since only EVAL_ variables pass. assess SKILL.md lines 65-67: workflow becomes subagent and the reason names the switch; legacy assess 2: the verdict does not suggest unsetting it. reason-names-switch needs disableWorkflows or .claude/settings.json on the reason line, words the prompt lacks; no-unset-suggestion fails a reply that proposes removing, flipping or re-enabling the switch. ran-availability-script is a with-only indicator. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, assess, outcome, availability, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "workflow-availability.sh runs and reports the settings switch off; the reply is verdict: subagent with a reason line naming the 60 scripts and the disableWorkflows switch in .claude/settings.json, and a shape line. Nothing suggests unsetting the switch; no agent or workflow is started."
---

/multi-agent:assess Audit all 60 hook scripts under hooks/ for unquoted variables, one finding list per script.
