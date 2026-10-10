---
description: "Resolve which model and effort each agent role gets in a multi-agent run (orchestrator, worker, verifier, retrieval) through the bundled defaults and the user, team and overlay config layers, and print it as fenced JSON with a single-agent and a fan-out variant per role and the layer that supplied each value. A fan-out stage never runs on a frontier model unless the config opts in. Use when: 'which model for the subagents', 'route the roles', 'what effort should the workers use', 'roles for the workflow args', 'model routing', 'is fan-out on Fable', or before a skill launches a workflow that takes args.roles."
argument-hint: "<role|all> [code|research|mechanical] [session=<alias>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Resolve model and effort per agent role for a multi-agent run
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/route.sh:*)"]
shell: bash
---

## Purpose

Workflow scripts and orchestrating skills read their model and effort choices
from here, so the choice lives in one role map with a recorded basis per
default, and a team or a person can change it without editing any script.
Keys, layers and the fan-out guard are owned by
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

## Arguments

- `<role|all>`: one of `orchestrator`, `worker`, `verifier`, `retrieval`, or
  `all` for the whole map.
- `code|research|mechanical`: optional workload; applies the role's
  `workloads.<w>` keys (research lowers the worker's effort by default).
- `session=<alias>`: the session model's alias. When the caller did not pass
  one, fill it from your own model ID: the family name in it (`opus`,
  `sonnet`, `haiku`, `fable`) is the alias. When you cannot tell, omit it; the
  resolver then treats the session as frontier, which keeps fan-out stages off
  the session model.

## Run

```bash
${CLAUDE_SKILL_DIR}/scripts/route.sh $ARGUMENTS
```

Append `session=<alias>` when `$ARGUMENTS` carries none and you know your model
family.

## Output

The JSON exactly as printed, in one fenced `json` block. Below it, one line per
role in this form:

```text
<role>: single <model|inherit: omit the model option> @ <effort>; fanout <model|inherit: omit the model option> @ <effort>
```

Write `inherit: omit the model option` wherever a variant's `omit_model` is
true, so a caller copying the line passes no model and the agent runs on the
session model. Then list every entry of `notes` (a skipped layer, a rejected
value, an ignored key) as written. Exit 2 means an unknown role or argument:
relay the valid roles from the error and stop.

A caller launching a workflow passes the JSON's `roles` object as
`args.roles`, unchanged. A caller spawning a subagent through the Agent tool
with no named type applies one variant to that call: it passes the variant's
model as `model`, or omits `model` when `omit_model` is true, and always
passes its effort as `effort`. A fork is not routed; it runs as the session.
An effort override or cap set for the session can still decide the level the
subagent runs at.

- **Pointer**: when a routed Agent dispatch runs at a different level than
  the one passed, or you need the values the call accepts, fetch
  [sub-agents: choose an effort level](https://code.claude.com/docs/en/sub-agents#choose-an-effort-level),
  [sub-agents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model)
  and [model config: set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: either sub-agents section changes which source wins
  for a subagent's model or effort, or the model-config section states
  whether an effort cap limits the per-call `effort`.

## What this skill does NOT do

- Write any configuration layer. That is `/multi-agent:setup apply`.
- Route a named agent. An agent dispatched by its own type, such as
  `implementation:implementer`, `implementation:scoped-implementer` or
  `implementation:phase-verifier`, owns its tier through its own frontmatter
  and its dispatcher's rules. The map governs generic `agent()` calls and
  Agent dispatches without a named type.
- Choose between a workflow and subagents. That is `/multi-agent:assess`.
- Check the defaults against upstream. That is `/multi-agent:audit-defaults`.

## Next

/multi-agent:audit-defaults
Rechecks a default that looks wrong for the current models.

## Gotchas

- Only aliases are accepted. A full model id in a layer is rejected and the
  layer below supplies the key, because an alias resolves per provider and an
  id does not.
- `fanout` and `single` differ only under a frontier or unknown session. Under
  an Opus session both say `inherit`, and `opus` would name the same model.
- The map never routes a named agent (`agentType`, or an Agent dispatch by
  subagent type), so the fan-out guard does not reach it on its own. A
  dispatcher that passes `model` or `effort` on the call overrides the
  definition's pins for that run (see the pointer under Output). Keeping a
  named agent such as `scoped-implementer` off a frontier session model, or
  at its pinned effort, is therefore that dispatcher's rule to keep.
- Team and overlay layers resolve against the repository root of the working
  directory. Inside a second worktree, run from that worktree.
