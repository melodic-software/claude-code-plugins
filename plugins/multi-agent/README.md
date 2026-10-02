# multi-agent

A Claude Code plugin that owns the marketplace's guidance on two questions:
whether a task should run as a workflow, and which model and effort each agent
in a multi-agent run gets. Other plugins call it rather than restating either
answer.

## The skills

| Skill | What it does |
|---|---|
| `/multi-agent:assess <task>` | Returns `workflow`, `subagent` or `single` with a one-line reason. Checks whether workflows are available in this session first; when they are not, `workflow` becomes `subagent`. Writes nothing. |
| `/multi-agent:route <role\|all> [code\|research\|mechanical] [session=<alias>]` | Resolves the role map through the config cascade and prints it as fenced JSON: per role a `single` and a `fanout` variant, each with model, effort and the layer that supplied them. `all` is the map a workflow reads from `args.roles`. |
| `/multi-agent:audit-defaults` | Fetches each bundled default's pointer and reports which defaults have drifted or whose recheck trigger has fired, with evidence and a proposed diff. Never edits a file. |

## How a workflow uses it

1. The calling skill runs `/multi-agent:route all session=<alias>`, where
   `<alias>` is the family of its own model (`claude-opus-5-5` is `opus`).
2. It passes the `roles` object of that JSON as `args.roles` to the Workflow
   tool.
3. The script merges `args.roles` over its own built-in fallbacks. A generic
   `agent()` call takes the `fanout` variant when its stage runs more than one
   agent and the `single` variant otherwise; it omits `opts.model` when the
   model is `inherit` and always passes `opts.effort`. A named agent
   (`agentType`) keeps the model and effort pinned in its own definition.

When `/multi-agent:route` is not in the session's skill listing, the caller
omits `args.roles`, the script's fallbacks apply, and the caller says once
that enabling this plugin makes the routing configurable.

`/review:fanout-sweep` in the `review` plugin is the first workflow built this
way.

## The fan-out guard

A stage that runs more than one agent never runs them on a frontier model by
default. Under a Fable session, or when the caller does not say which model
the session runs, every fan-out variant names `opus`; a single synthesis or
judge agent may still inherit the session model. The verifier role stays at
least as strong as what it checks: `opus` verifiers over `opus` workers. Turning
the guard off (`fanout.frontier_guard: false`) is an explicit opt-in to
frontier fan-outs. The basis for each default is recorded beside it in
[`reference/defaults.yaml`](reference/defaults.yaml).

## Configuration

One surface, layered user-global (`~/.claude/multi-agent.yaml`), team (a
```` ```yaml config ```` block in `docs/conventions/multi-agent.md`, else
`.claude/multi-agent.yaml`) and a gitignored overlay
(`.claude/multi-agent.local.yaml`), each overriding the bundled defaults per
key. Keys, values and layering: [`reference/config.md`](reference/config.md).

## Requirements

- **Bash, awk and git.** The resolver parses the YAML subset with awk, so no
  `jq`, `yq` or Python is needed.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install multi-agent@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
