# One plugin owns workflow and model-routing guidance

- Status: accepted
- Date: 2026-10-02

## Context

Several plugins dispatch many agents: `review:fanout`, `planning`, `discovery:research-deep`,
`testing`, `code-tidying:batch-simplify`. Each needs two answers: whether the work should run as a
workflow, as delegated subagents, or in one context, and which model and effort each agent gets.
Before this decision each skill answered both in its own text. The review fan-out script hard-coded
`model: 'sonnet'` for its extractor, and the tier table in `docs/plugin-philosophy.md` was the
only shared statement. Two failure modes followed:

- The answers drift apart, because each copy is edited on its own schedule and the upstream
  guidance (the workflows page, the bundled `/workflow-authoring` skill, the model cost page) moves
  with each model generation.
- A frontier session fans out on its own model. A generic `agent()` call with no `model` inherits
  the session model, so a Fable session running a workflow spawns many Fable agents. The owner's
  requirement is that a stage running more than one agent never does that by default.

Claude Code runs plugin workflows by namespace with structured `args` (`/<plugin>:<name>`), and
Anthropic's `claude-security` plugin launches its scan workflow that way from a skill that grants
`Workflow(claude-security:scan)`. A workflow script cannot read files or see the session model, so
whatever routing it applies has to arrive in `args`.

## Decision

1. **The `multi-agent` plugin owns both answers.** `/multi-agent:assess` returns `workflow`,
   `subagent` or `single` with a one-line reason and checks that workflows are available.
   `/multi-agent:route` returns the resolved role map. Other plugins call these skills and do not
   restate the rule or the defaults.
2. **Routing is a role map with a recorded basis.** Roles are `orchestrator`, `worker`, `verifier`
   and `retrieval`. Each bundled default in `plugins/multi-agent/reference/defaults.yaml` carries a
   pointer, an as-of date and a recheck trigger, and `/multi-agent:audit-defaults` rechecks them
   and proposes changes without applying them. Consumers override per key through the config
   cascade: user-global, team (the docs convention block per ADR 0044, else `.claude/`), and a
   personal overlay. Models are aliases only.
3. **Workflows receive the map through `args.roles`.** The calling skill runs
   `/multi-agent:route all session=<alias>` and passes the `roles` object. The script merges it
   over built-in fallbacks, so it runs when the plugin is absent. A generic `agent()` call always
   passes `effort` and omits `model` when the role says `inherit`. A named agent keeps the model and
   effort pinned in its own definition.
4. **The fan-out guard is on by default.** Each role resolves to a `single` and a `fanout` variant.
   Under a frontier session, or when the caller does not name the session model, a fan-out variant
   that would inherit or name a frontier model names `opus` instead. A single synthesis or judge
   agent may inherit. Turning the guard off is an explicit configuration opt-in.

## Alternatives considered

- **Each plugin keeps its own routing text.** Rejected: it is the drift this decision removes, and
  it gives the frontier guard no single place to live.
- **State the guidance only in `docs/plugin-philosophy.md`.** Rejected: a repository document is
  not installed with the plugins, so a consumer repository never sees it, and a workflow script
  cannot read it at run time.
- **Put it in `session-flow:orchestrate`.** Rejected: that skill's imperatives are exported into
  worker briefs and must stay free of any one plugin's configuration, and it has no resolver or
  config surface to carry a per-key cascade.

## Consequences

- Workflow-dispatching plugins gain an optional dependency on `multi-agent`. When it is not
  installed they omit `args.roles`, the script's fallbacks apply, and they say once that enabling
  it makes routing configurable.
- `review:fanout-sweep` is the first consumer. Planning, research, testing and drift-audit
  workflows follow in their own changes.
- `docs/plugin-philosophy.md` and `session-flow:orchestrate` point at this plugin rather than
  restating its defaults; those edits land in their own changes.
- A new model generation is a recheck event for the defaults, handled by `/multi-agent:audit-defaults`
  and a reviewed edit to `defaults.yaml`, not by edits across plugins.
