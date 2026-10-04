# multi-agent configuration surface

Owner document for the role map the `multi-agent` skills resolve. The bundled
values live in [`defaults.yaml`](defaults.yaml); a consumer layer overrides
them per key. How layers are found and ordered across the marketplace is the
[config-cascade convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/config-cascade/README.md);
this page owns the keys.

## Layers

| Layer | Path |
|---|---|
| Bundled | `${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml` |
| User-global | `~/.claude/multi-agent.yaml` |
| Team | the ```` ```yaml config ```` block in `docs/conventions/multi-agent.md`, else `.claude/multi-agent.yaml` |
| Personal overlay | `.claude/multi-agent.local.yaml` (gitignored) |

Later layers win per key. Team and overlay are read only when the root is a
repository that is neither `$HOME` nor an ancestor of it
(`lib/config-root.sh`). When both team files exist the docs block wins and the
resolver names both. Every layer declares `schema: 1`; a layer that does not
parse or names another schema is skipped and named in `notes`, and the layers
around it still apply. The format is a YAML subset: nested mappings, scalars,
comments. No lists. `/multi-agent:setup apply` writes a layer after a preview
and an explicit yes.

## Keys

| Key | Values | Bundled |
|---|---|---|
| `roles.<role>.model` | `inherit`, or an alias: `opus`, `sonnet`, `haiku`, `fable`, `best` | per role |
| `roles.<role>.effort` | `low`, `medium`, `high`, `xhigh`, `max` | per role |
| `roles.<role>.workloads.<w>.model` / `.effort` | as above; `<w>` is `code`, `research` or `mechanical` | `worker.workloads.research.effort: low`, `worker.workloads.mechanical.model: sonnet` (opt out with `roles.worker.workloads.mechanical.model: inherit` in any layer) |
| `frontier` | comma-separated aliases treated as frontier | `fable,best` |
| `fanout.frontier_guard` | `true`, `false` | `true` |
| `fanout.model` | an alias | `opus` |

Roles are `orchestrator`, `worker`, `verifier` and `retrieval`. A layer naming
another role, workload or key is reported and ignored. A full model id
(`claude-opus-5-5`) is rejected, so a role map stays portable across providers.
`inherit` means the calling workflow omits `opts.model`. For what an alias
resolves to per provider, see
[model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases);
for the model an agent with no `model` runs on, see
[workflows: cost](https://code.claude.com/docs/en/workflows#cost). Both as of
2026-10-02; recheck when either section changes.

`pointer*`, `as_of` and `recheck` record where each bundled default's basis
lives. They are read from the bundled layer only, by
`/multi-agent:audit-defaults`.

## Tiering by difficulty

Route a stage by how hard its work is, not by its topic. Mechanical work
(renames, formatting, one transformation applied at many sites, log filtering)
goes through the `mechanical` workload, which runs the worker on `sonnet` by
default. The hardest stage that one agent runs (a final synthesis, a judge, a
design decision) takes the role's `single` variant, which keeps the role's own
model. Everything else takes the role's default for its workload. The bundled
`mechanical` model rests on
[costs: choose the right model](https://code.claude.com/docs/en/costs#choose-the-right-model),
as of 2026-10-04; recheck when that section changes its model split.

## Where effort applies

Role effort reaches workflow `agent()` calls, which pass `opts.effort`
explicitly. An Agent tool dispatch has no effort parameter: it runs at the
dispatched agent's `effort` frontmatter, or at the session's level when the
agent sets none. route reads no settings file, so the effort it prints is the
level a caller asks for, before any cap. A loop lane's level is its own
`lanes[].effort`, not the `orchestrator` role.

## Hard cap

`maxEffortLevel` is the consumer's hard cap over every role and every named
agent's pinned effort. It can be set in any settings scope, the lowest value
across scopes applies, and a per-model cap sits in that model's
`modelSettings` entry. Any higher level, from a role, frontmatter or the
session, runs at the cap. An organization effort limit for a model applies
alongside it, and the lower of the two wins.

- Pointer: [settings reference: `maxEffortLevel`](https://code.claude.com/docs/en/settings-reference#maxeffortlevel);
  [model config: organization effort limits](https://code.claude.com/docs/en/model-config#organization-effort-limits)
- As of: 2026-10-04
- Recheck: either entry changes which scopes can set the cap, how scopes
  combine, or which effort sources it covers.

## The fan-out guard

Every role resolves to two variants. `single` serves a stage that runs one
agent (a final synthesis or judge); `fanout` serves a stage that runs more than
one. With `fanout.frontier_guard: true`, a fan-out variant whose model would be
`inherit` under a frontier session, or under a session the caller did not name,
or that names a frontier alias, takes `fanout.model` instead. So a frontier
session never fans out on its own model. Under an Opus session `opus` and
`inherit` name the same model, so the guard changes nothing there.

Setting `fanout.frontier_guard: false` is an explicit opt-in to frontier
fan-outs. Set it on the layer whose scope you mean: the overlay for one
checkout, the user-global file for every repository on one machine.

## Example team block

````markdown
```yaml config
schema: 1
roles:
  worker:
    effort: high
fanout:
  frontier_guard: true
```
````
