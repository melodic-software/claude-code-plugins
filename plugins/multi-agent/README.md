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
| `/multi-agent:audit-defaults [<role>\|fanout\|repo]` | Fetches each bundled default's pointer and reports which defaults have drifted or whose recheck trigger has fired, with evidence and a proposed diff. `repo` checks the repository's own model, effort, subagent and workflow statements against upstream instead. Runs the `multi-agent:drift-audit` workflow when workflows are available. Never edits a file. |
| `/multi-agent:check` | Reports whether `node` resolves, whether `hooks/hooks.json` registers the fetch gate on `WebFetch`, and whether the gate denies a sample off-host drift-checker fetch. Read-only; installs nothing. |
| `/multi-agent:setup [check\|apply]` | `check` prints the resolved map and whether the personal overlay is gitignored. `apply` previews a change to the user, team or local layer as a diff, writes it on your explicit yes, and shows the map before and after. Run by hand only. |

## How a workflow uses it

1. The calling skill runs `/multi-agent:route all session=<alias>`, where
   `<alias>` is the family of its own model (`claude-opus-5-5` is `opus`).
2. It passes the `roles` object of that JSON as `args.roles` to the Workflow
   tool.
3. The script merges `args.roles` over its own built-in fallbacks. A generic
   `agent()` call takes the `fanout` variant when its stage runs more than one
   agent and the `single` variant otherwise; it omits `opts.model` when the
   model is `inherit` and always passes `opts.effort`.

The map governs generic `agent()` calls and Agent dispatches that name no
agent type. A named agent, such as `implementation:implementer`,
`implementation:scoped-implementer` or `implementation:phase-verifier`, owns
its tier through its own frontmatter and its dispatcher's rules, and the
fan-out guard does not reach it.

When `/multi-agent:route` is not in the session's skill listing, the caller
omits `args.roles`, the script's fallbacks apply, and the caller says once
that enabling this plugin makes the routing configurable.

`/review:fanout-sweep` in the `review` plugin is the first workflow built this
way.

## The drift-audit workflow

`multi-agent:drift-audit` is the evidence pass behind `/multi-agent:audit-defaults`.
Finders (one per default owner, or one per area of the repository) fetch the
upstream sources and judge each claim; plain code dedups what they find; then
three skeptics per batch try to refute each finding, and a majority decides it.
In repo mode a `multi-agent:drift-reader` agent (Read, Grep, Glob) first quotes
each area's claims, and the finders see only those quotes. Finders and skeptics
run as `multi-agent:drift-checker` (WebFetch only, no search). Neither agent
has a shell or can edit, write or spawn agents, and none holds both file and
web access: the only repository text a checker holds is the quoted claim
lines, and the hook below confines its fetches. The
workflow returns findings and, for the defaults, a proposed diff; applying any
of it is a reviewed edit.

A `PreToolUse` hook on `WebFetch` (`hooks/drift-checker-fetch-gate.mjs`) makes
the host rule a gate: inside a `drift-checker` subagent it denies any fetch
that is not an https URL on a first-party docs host with no query string. Every
other agent and the main thread pass through. The workflow drops any source
outside those hosts before a stage runs.

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
key. `/multi-agent:setup` writes any of the three. Keys, values and layering:
[`reference/config.md`](reference/config.md).

## Requirements

- **Bash 3.2 or later, awk and git.** The resolver parses the YAML subset with awk, so no
  `jq`, `yq` or Python is needed.
- **Node.js** for the `drift-checker` fetch gate hook. Without `node` the gate fails open: the hook
  cannot start, Claude Code shows a non-blocking hook error notice, and the drift checker's fetches
  are held to first-party docs hosts only by the workflow's source filter and the agent's prompt.
  `/multi-agent:check` reports whether `node` resolves and the gate is registered.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install multi-agent@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
