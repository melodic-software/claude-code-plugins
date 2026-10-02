---
description: "Decide whether a task should run as a workflow, as delegated subagents, or in this single context, and say why in one line; checks first whether workflows are available in this session and downgrades `workflow` to `subagent` when they are not. Writes nothing. Use when: 'should this be a workflow', 'workflow or subagents', 'is this worth a workflow', 'how should I orchestrate this', 'fan this out or do it inline', 'is the Workflow tool available', or before a skill launches a workflow."
argument-hint: "<task description>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Decide workflow, subagents or one context for a task
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/workflow-availability.sh:*)", "Read"]
shell: bash
---

## Purpose

One verdict for one task: `workflow`, `subagent` or `single`, with a one-line
reason. A skill that is about to launch a workflow, or a person deciding how to
run a large task, asks here instead of restating the rule.

## The rule

Our decision: a **workflow** only when the work outgrows one context or repeats
the same steps over many independent items, so that holding the loop in a
script beats holding it in a conversation. A **subagent** when a few delegated
tasks fit the turn, or when the work is one dependent chain that still needs a
fresh context. **Single** when the task fits this context and is one dependent
chain.

The comparison this rule rests on lives upstream; read it there when a case is
close rather than recalling it:

- Pointer: <https://code.claude.com/docs/en/workflows#when-to-use-a-workflow>
- As of: 2026-10-02
- Recheck: the page changes its comparison of subagents, skills, agent teams
  and workflows, or adds a scale or interruption row.

## Steps

1. **Availability.** Run:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-availability.sh
   ```

   It reads the switches that turn workflows off (the
   `CLAUDE_CODE_DISABLE_WORKFLOWS` variable and `disableWorkflows` in the
   user, project and local settings files) and prints `verdict off` or
   `verdict not-off`. Then look at the tools you can call right now: workflows
   are available only when the verdict is `not-off` **and** `Workflow` is one
   of them. A name in a grant or in this text does not count. Managed settings
   and a subagent context both remove the tool, so its absence is the check
   that covers them. Where the switches are documented:
   <https://code.claude.com/docs/en/workflows#turn-workflows-off> (as of
   2026-10-02; recheck when a new switch appears there). Done when you can
   say `available` or name the switch or the missing tool.
2. **Size the task.** Name the item count or the context it needs, and whether
   the steps depend on each other. Read only what you need to count. Done when
   you have a number or a context estimate and a dependency shape.
3. **Verdict.** Apply the rule. When workflows are unavailable, `workflow`
   becomes `subagent`, and the reason names the switch or the missing tool.
   Done when the two output lines are written.

## Output

Two lines, nothing else:

```text
verdict: <workflow|subagent|single>
reason: <one line naming the size, the dependency shape, and any downgrade>
```

## What this skill does NOT do

- Launch a workflow, spawn an agent, or write a file.
- Pick models or effort. That is `/multi-agent:route`.

## Next

- workflow: /multi-agent:route all session=<alias>.
- subagent or single: /session-flow:orchestrate.

## Gotchas

- A skill run inside a subagent does not see the Workflow tool even when
  workflows are on, so it reports `subagent`. That is correct for that
  context: the main session can still run the workflow.
- `verdict not-off` from the script is not availability. The tool check in
  step 1 is the half that decides.
- Effort and size scale the verdict, not the topic: a review of three files is
  `single` even though reviews are a common workflow shape.
