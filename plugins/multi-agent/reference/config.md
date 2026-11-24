# multi-agent configuration

Owner document for the role map the `multi-agent` skills resolve. The bundled
values live in [`defaults.yaml`](defaults.yaml); a consumer layer overrides
them per key. How layers are found and ordered across the marketplace is the
[config-cascade convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md);
this page owns the keys.

## Layers

| Layer | Path |
|---|---|
| Bundled | `${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml` |
| `userConfig` (`user-config`) | the file the `role_map_file` option names; unset means no user layer |
| Team | `<home>/multi-agent.yaml`, `<home>` being the convention home the repository binds, else `docs/conventions` |
| Personal override | `<home>/multi-agent.local.yaml` (gitignored by `<home>/**/*.local.*`) |

The user layer is a nested map of the same keys as the team file, which no
scalar `userConfig` option can hold, so the plugin's one `role_map_file`
option (type `file`) names a file that keeps it, and `/config` sets it.

**Old paths, read during the migration window.** While no new file supplies
the user layer, `~/.claude/multi-agent.yaml` still does, named `user-global`
in `source`; while `<home>/multi-agent.local.yaml` is absent,
`.claude/multi-agent.local.yaml` still supplies the personal override. Every
run names each old file it finds, read or not, in `notes`, with its new
location and `/multi-agent:setup apply --migrate`, which moves the file after a
preview and a yes and then deletes it. A later change removes these reads.

Later layers win per key. Team and personal override are read only when the root is a
repository that is neither `$HOME` nor an ancestor of it
(`lib/config-root.sh`). The team file is validated by
[`schemas/multi-agent.schema.json`](../schemas/multi-agent.schema.json). The
resolver no longer reads the old team locations, the config block in
`docs/conventions/multi-agent.md` and `.claude/multi-agent.yaml`;
`/multi-agent:setup check` names each one it finds. While the team YAML is
absent, the first `/multi-agent:setup apply --layer team` write copies the keys
of one of them, the block when there is one, into the new YAML and leaves the
old file in place; `/multi-agent:setup apply --migrate` moves
`.claude/multi-agent.yaml` into the YAML and deletes it. Every layer declares `schema: 1`; a layer that does not
parse or names another schema is skipped and named in `notes`, and the layers
around it still apply. The format is a YAML subset: nested mappings, block or
flow sequences, scalars, comments. `/multi-agent:setup apply` writes a layer
after a preview and an explicit yes.

## Keys

| Key | Values | Bundled |
|---|---|---|
| `roles.<role>.model` | `inherit`, or an alias: `opus`, `sonnet`, `haiku`, `fable` | per role |
| `roles.<role>.effort` | `low`, `medium`, `high`, `xhigh`, `max` | per role |
| `workloads.<w>` | `true` declares workload `<w>`, `false` withdraws it; `<w>` holds only letters, digits, `_` and `-`, and does not start with `-` | `code`, `research` and `mechanical` declared |
| `roles.<role>.workloads.<w>.model` / `.effort` | as above; `<w>` is a declared workload | `worker.workloads.mechanical.model: sonnet` (opt out with `roles.worker.workloads.mechanical.model: inherit` in any layer); a layer may set others, for example `worker.workloads.mechanical.effort: low` |
| `frontier` | comma-separated aliases treated as frontier | `fable` |
| `fanout.frontier_guard` | `true`, `false` | `true` |
| `fanout.model` | an alias | `opus` |
| `vendors.routing` | `true`, `false` | `true` |
| `vendors.trials` | `true`, `false` | `false` |
| `vendors.auto_delegation` | `true`, `false` | `false` |
| `vendors.trials_prove` | integer >= 1 | unset |
| `vendors.trials_fail` | integer >= 2 (`1` is rejected) | unset |
| `vendors.<vendor>.in_use` | `true`, `false` (`<vendor>` is `claude`, `codex` or `antigravity`) | unset |
| `vendors.<vendor>.rank` | integer (lower rank comes first in vendor order) | unset |
| `vendors.sources.<id>.enabled` | `true`, `false` (`<id>` matches `^[a-z0-9][a-z0-9-]*$`) | unset (uses the row's `enabled`, default `true`) |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` |

`verification` is not part of the role map. It sets whether `/multi-agent:audit-defaults` runs
its skeptic panel: `light` and `off` skip it and report every finding `unverified`, so no diff is
proposed. It is read from the team file at the default branch only, through
`lib/read-verification.sh`; the resolver ignores it in every layer, and the user and
personal files cannot set it. A skill entry beats the plugin value
([verification level](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/verification-level/README.md)).

Roles are `orchestrator`, `worker`, `verifier` and `retrieval`. A layer naming
another role or key is reported and ignored, and so is a workload no layer
declares. A declaration in any layer covers values set in every layer, so a
team layer can declare a workload that a personal override tunes. A full model id
(`claude-opus-5-5`) is rejected, so a role map stays portable across providers.
Whether a role may name `haiku` is decided in
[`routing-rubric.md`](routing-rubric.md); the resolver accepts it and adds a
note.
`inherit` means the calling workflow omits `opts.model`. For what an alias
resolves to per provider, see
[model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases);
for the model an agent with no `model` runs on, see
[workflows: cost](https://code.claude.com/docs/en/workflows#cost).

For the values the subagent `model` field accepts, and the order in which a
subagent with no `model` resolves one, see
[sub-agents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model).

The `effort` values are the full set this resolver accepts; which of them a
spawn can use depends on the model it runs on. For each model's supported
levels, see
[model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level).

`pointer*`, `basis_*`, `claim_*`, `reason_*`, `as_of` and `recheck` record
where each bundled default's basis lives. A role's `basis_model` and
`basis_effort` say whether an upstream statement sets that value (`upstream`,
with `pointer_<field>` and `claim_<field>`) or it is a judgment (`judgment`,
with `reason_<field>`); a `workloads.<w>.<field>` value records the same keys
on its role as `basis_<w>_<field>` and so on. The resolver prints the basis
beside each value, and a guarded fan-out model takes `fanout.model`'s basis. They
are read from the bundled layer only, and `/multi-agent:audit-defaults` checks
each upstream pointer against its value.

## Tiering by difficulty

Route a stage by how hard its work is, not by its topic. Mechanical work
(renames, formatting, one transformation applied at many sites, log filtering)
goes through the `mechanical` workload, which runs the worker on `sonnet` by
default. The hardest stage that one agent runs (a final synthesis, a judge, a
design decision) takes the role's `single` variant, which keeps the role's own
model. Everything else takes the role's default for its workload. The bundled
`mechanical` model is this repository's judgment, weighing the well-scoped coding row of
[which Claude model should you build with: pick a model by task](https://claude.dev/blog/which-claude-model-should-you-build-with#pick-a-model-by-task),
as of 2026-11-09; recheck when that row changes its starting model.

## Where effort applies

Role effort reaches workflow `agent()` calls, which pass `opts.effort`
explicitly, and Agent tool dispatches with no named type, which pass it as the
per-spawn `effort` parameter (route's Output section). Which level a named
agent runs at, given the call, its `effort` frontmatter and the session, is
Claude Code's precedence, read at the pointers below. route reads no settings
file, so the effort it prints is the level a caller asks for, before any cap. A
loop lane's level is its own `lanes[].effort`, not the `orchestrator` role.

- Pointer: for effort precedence and what a subagent inherits, read
  [sub-agents: choose an effort level](https://code.claude.com/docs/en/sub-agents#choose-an-effort-level),
  [sub-agents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)
  and [model config: effort level of subagents and teammates](https://code.claude.com/docs/en/model-config#effort-level-of-subagents-and-teammates)

## Hard cap

A consumer caps effort with `maxEffortLevel`. This plugin neither reads nor
overrides it, so a role's effort is a request the cap may lower. How the cap
applies, which settings scopes set it, how values across scopes and a model's
`modelSettings` entry combine, and how an organization effort limit applies
alongside it are read at the pointers below.

- Pointer: [settings reference: `maxEffortLevel`](https://code.claude.com/docs/en/settings-reference#maxeffortlevel);
  [model config: organization effort limits](https://code.claude.com/docs/en/model-config#organization-effort-limits)

## The fan-out guard

Every role resolves to two variants. `single` serves a stage that runs one
agent (a final synthesis or judge); `fanout` serves a stage that runs more than
one. With `fanout.frontier_guard: true`, a fan-out variant whose model would be
`inherit` under a frontier session, or under a session the caller did not name,
or that names a frontier alias, takes `fanout.model` instead. So the resolver
never emits a frontier session's own model for a fan-out stage. What the agent
runs on is the harness's call: see
[sub-agents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model) and
[run every subagent on one model](https://code.claude.com/docs/en/sub-agents#run-every-subagent-on-one-model).
Where `fanout.model` and `inherit` resolve to the same model, the guard
changes nothing.

Setting `fanout.frontier_guard: false` is an explicit opt-in to frontier
fan-outs. Set it on the layer whose scope you mean: the personal override for one
checkout, the user file for every repository you work in.

Before a fan-out wider than about four workers, run one worker as a pilot and
confirm plan usage remains for the rest: a usage limit reached mid-fan-out
stops every worker at once.

## Vendor routing settings and team benchmark rows

The `vendors` block resolves across the same layers (`bundled`, `user-config`,
`team`, `personal-override`) under the same invalid-value rule: an invalid
value (such as `trials_fail: 1`) is rejected with a note, and the layer below
keeps the key. `/multi-agent:setup apply` runs the same validation before
writing.

- `vendors.routing: false`: `/multi-agent:route vendors` reports that routing is
  off and recommends nothing (including work Claude cannot do), while trials
  pause and keep their data.
- `vendors.trials: true` with `trials_prove` or `trials_fail` unset: trials stay
  inactive and routing emits one note saying so.
- `vendors.<vendor>.in_use`: `false` skips the vendor silently; `true` when the
  vendor is unavailable in `external-agents models` emits one note line. A
  vendor whose `breaker.open` is `true` is skipped with one note naming
  `reset_at` (unless `in_use: false`).
- `vendors.auto_delegation`: `false` (default) recommends the chosen vendor and
  shows how to run it; `true` runs `external-agents run <product> --use task --mode write`
  for `image` requests (using a prompt built strictly from the user's task and
  naming the vendor's built-in image tool), reports the CLI and output path, and
  reviews the image before recording any trial verdict. Only the user layer
  (`role_map_file`) sets it; a team or personal-override value, both files inside a
  repository, is ignored with a note.
- `vendors.auto_delegation` for `coding`, `web-ui` and `knowledge` work: `true`
  runs a caller's brief through route's `delegate` script (`--use investigate`
  read-only, or `--use task --mode write`) per the Caller contract in `vendors.md`.
- `vendors.sources.<id>.enabled: false`: disables a shipped or team benchmark
  row during fetch and decision.

A repository may append team benchmark rows in
`<repo>/docs/conventions/multi-agent/benchmarks.json` (resolved from
`git rev-parse --show-toplevel`, skipped outside a git repository). The file
uses the same closed schema as [`benchmarks.json`](benchmarks.json)
([`schemas/benchmark-registry.schema.json`](../schemas/benchmark-registry.schema.json)).
Team rows are appended after the shipped rows; any team row whose `id` matches a
shipped row id is refused with a note.

## Trial state

Trial notes, per-pair outcomes (`proven` or `failed`), and seen model ids live per machine under
`<data>/vendor-state/` (`trials/`, `outcomes/`, `rechecks/`, `seen/`), where `<data>` resolves from the
installed plugin path first (`<...>/plugins/data/multi-agent-<marketplace>` derived from
`<...>/plugins/cache/<marketplace>/multi-agent/<version>/`), then `CLAUDE_PLUGIN_DATA` only when
its basename starts with `multi-agent-`. Outcome files are machine-neutral, one file per
`vendor:model:version:effort:work_type` key. Routine routing writes nothing.

A proven pair keeps recording Claude's verdicts in `rechecks/`, holding only its newest
`trials_prove` results, and goes back to trial when `trials_fail` of them are rejected. The user can
also send a pair back by hand:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/route/scripts/vendor-state send-back --key <vendor>:<model>:<version>:<effort>:<work_type>
```

## Example team file

This `docs/conventions/multi-agent.yaml` raises the worker's effort and
declares a `deep` workload, which a caller selects with
`/multi-agent:route worker deep`. A consumer maps its own labels (an issue's
complexity, say) onto workloads in its own convention; the plugin ships no
such mapping.

```yaml
schema: 1
workloads:
  deep: true
roles:
  worker:
    effort: high
    workloads:
      deep:
        model: opus
        effort: xhigh
fanout:
  frontier_guard: true
```
