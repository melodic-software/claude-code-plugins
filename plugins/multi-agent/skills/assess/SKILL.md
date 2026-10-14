---
description: "Workflow, subagent or single-context verdict for a task, with a one-line reason; downgrades `workflow` to `subagent` when workflows are unavailable in this session. Writes nothing. Use when asked 'should this be a workflow', 'workflow or subagents', 'is this worth a workflow', 'how should I orchestrate this', 'fan this out or do it inline' or 'is the Workflow tool available', or before a skill launches a workflow."
argument-hint: "<task description>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Decide workflow, subagents or one context for a task
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/workflow-availability.sh:*)", "Read"]
shell: bash
---

## The rule

A **workflow** only when the work outgrows one context or repeats the same
steps over many independent items, so that holding the loop in a script beats
holding it in a conversation. A **subagent** when a few delegated tasks fit the
turn, or when the work is one dependent chain that still needs a fresh context.
**Single** when the task fits this context and is one dependent chain. Size and
effort set the verdict, not the topic: a review of three files is `single` even
though reviews are a common workflow shape.

A run of more than one agent also has a **shape**:

- **sections**: each agent gets a separate slice of the work, and the results
  are combined.
- **race**: agents get identical briefs and one result is picked. The selection
  rule is stated before any agent is spawned: first to pass a stated check,
  rank all results, or best-of a stated criterion.
- **mixed**: sections, some of which run as races.

`shape:` describes how the agents divide the work, not their count. A run's
total worker count is not its concurrency cap: forty sections under a cap of
four are forty workers, four at a time. When they differ, give both numbers in
the reason.

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

   It reads the off switches the script knows and prints `verdict off` or
   `verdict not-off`. Then look at the tools you can call right now: workflows
   are available only when the verdict is `not-off` **and** `Workflow` is one
   of them. A name in a grant or in this text does not count. The tool's
   absence covers every switch the script cannot see. Where the switches are
   documented:
   <https://code.claude.com/docs/en/workflows#turn-workflows-off> (as of
   2026-10-02; recheck when a new switch appears there). End this step able to
   say `available` or name the switch or the missing tool.
2. **Size the task.** Name the item count or the context it needs, and whether
   the steps depend on each other. Read only what you need to count.
3. **Verdict.** Apply the rule. When workflows are unavailable, `workflow`
   becomes `subagent`, and the reason names the switch or the missing tool.
   Done when the verdict and reason lines are written.
4. **Shape.** With a `workflow` or `subagent` verdict, name the run's shape.
   For a race or a mixed run, take the selection rule from the task; when the
   task states none, write `race (no selection rule stated)` and say in the
   reason that the race must not start until one is stated: picking a winner
   after reading the results lets the reading choose the rule. Done when the
   shape line is written, or the verdict is `single`.

## Output

Two lines for a `single` verdict, three for `workflow` or `subagent`, nothing
else:

```text
verdict: <workflow|subagent|single>
reason: <one line naming the size, the dependency shape, and any downgrade>
shape: <sections|race (<selection rule>)|mixed>
```

## What this skill does NOT do

- Launch a workflow, spawn an agent, or write a file.
- Pick models or effort. That is `/multi-agent:route`.

## Next

- workflow: /multi-agent:route all session=<alias>.
- subagent or single: /session-flow:orchestrate.

## Gotchas

- When the Workflow tool is not callable here, report `subagent` even if
  workflows are on elsewhere: the main session may still have the tool.
