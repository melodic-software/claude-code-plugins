# planning: settings

The key contract for the `planning` plugin. Every key is optional: with nothing set, each skill
runs on the defaults below.

## Layers

Resolved lowest first; a later layer wins
([ADR 0064](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0064-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/planning.yaml` at the repository root, tracked, validated by [`schemas/planning.schema.json`](../schemas/planning.schema.json) |

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill resolves
each key in its own text, with no reader script, and reports one line naming the value and the
layer that supplied it. `/planning:setup apply <key>=<value>` writes the repository file after
validating it against the schema, and shows the diff and asks before it changes an existing one.

**Root rule.** The repository file is read only when the working directory is inside a git working
tree whose root is neither `$HOME` nor an ancestor of it. Otherwise the repository layer is skipped
and the report says so; `/planning:setup apply` refuses to write there.

**Unset and invalid values.** A missing file or key leaves that layer unset. A literal, unexpanded
`${user_config.<key>}` means the user layer is unset, and a user value equal to the default is
reported as the default, since the two cannot be told apart. A value outside the key's list, in
either layer, is named with its file (or `userConfig`), key and value, and that layer is dropped: a
valid higher layer still wins, with none the key resolves its default, and a lower layer's value is
never used in its place. An invalid value never stops the run.

## Keys

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `plan_store` | `local`, `tracker` | `local` | `/planning:plan`, final persist step: `tracker` also publishes the approved plan to the claimed work item through `/work-items:track publish-plan` | repository file over user config over default |
| `phase_order` | `composed`, `subtraction-first`, `riskiest-first` | `composed` | `/planning:plan` Step 2, after build-technique selection: the order of the plan's phases | repository file over user config over default |
| `scaffold_stubs` | `true`, `false` (bare YAML booleans; a quoted `"true"` is invalid) | `false` | `/planning:design` handoff: names the stub files and their signatures; `/planning:plan` Step 2: places the stub phase | repository file over user config over default |
| `time_units` | `true`, `false` (bare YAML booleans) | `false` | the procedure in [`../context/problem-framing.md`](../context/problem-framing.md) "Time units": whether an estimate or budget of work may be stated in hours, days or weeks | repository file over user config over default |
| `pre_confirmed_label` | a tracker label name (non-empty string) | unset | same procedure, "Pre-confirmed": the label that marks an item's stated problem confirmed in an unattended run | repository file over default |
| `work_size` | an object with `appetite`, `size`, `uncertainty`, each a map of level name to a quoted one-line description | appetite and size `Small`, `Medium`, `Large`; uncertainty `Known`, `Knowable`, `Unknown`; descriptions below | same procedure, "Work size": the levels the Brief's `### Work size` names | repository file over default |
| `shared_session.uploads` | `true`, `false` | `false` | `/planning:interview` shared lane, at start: guests may offer files | repository file over default |
| `shared_session.names` | `full`, `initials`, `someone` | `full` | same: what guests see of who answered and voted | repository file over default |
| `shared_session.digest_names` | `true`, `false` | `false` | same: whether the round sent to Claude names who answered, except people a question is aimed at, who are always named | repository file over default |
| `shared_session.claude_take` | `answer-first`, `always` | `answer-first` | same: when people see Claude's suggestion cards | repository file over default |
| `shared_session.voting` | `true`, `false` | `true` | same: people vote on answers | repository file over default |
| `shared_session.signoff` | `true`, `false` | `false` | same: a leader's lock needs everyone's agreement | repository file over default |
| `shared_session.chat` | `true`, `false` | `true` | same: the side chat, never sent to Claude | repository file over default |
| `shared_session.follow` | `true`, `false` | `true` | same: pages move to a new round when it arrives | repository file over default |
| `shared_session.accent` | `teal`, `indigo`, `violet`, `amber` | `teal` | same: the page's accent color | repository file over default |
| `shared_session_open_browser` | `true`, `false` | `true` | same: opens the owner's page in the browser at start | user config over default |

`phase_order` values, in phase order:

- `composed`: dead code the change touches is removed first (a bug fix skips this), then the
  integration slice, then the riskiest remaining unknown, then scaffold, then the remaining
  features.
- `subtraction-first`: dead-code removal, then scaffold, then features.
- `riskiest-first`: the step whose failure would invalidate the most downstream work, then the
  rest in dependency order.

Under every value a phase that needs another phase's output still follows it.

`scaffold_stubs: true` adds a stub commit ahead of the work: `/planning:design` lists each stub
file with the signatures it declares, and `/planning:plan` makes those stubs one phase, placed right
after the dead-code removal step, or first when the plan has none. A stub body is the language's
ordinary not-implemented form. When the stubs leave the build red, that phase carries a
`**Planned breakage:**` line naming the stub paths. `false` adds no stub phase.

`time_units` governs estimates and budgets of work only. Practice cadence ("integrate at least
daily") and measurement windows ("within 30 days of launch") are not estimates and are written as
needed under either value.

`work_size` lives in the repository file only and is edited by hand: `/planning:setup apply`
writes no maps. A dimension set there replaces that dimension's default as a whole; levels are
never merged. Levels keep the order written, and the last `size` level is the split trigger,
whatever it is named. Write each description as a quoted string. The defaults:

```yaml
work_size:
  appetite:
    Small: "A contained change the human will spend little on."
    Medium: "A real piece of work the human will fund with some care."
    Large: "A major investment the human accepts."
  size:
    Small: "One focused change with few moving parts."
    Medium: "Several coordinated changes inside one deliverable."
    Large: "Too big for one deliverable: split it."
  uncertainty:
    Known: "The approach and its unknowns are understood."
    Knowable: "The open points can be settled by looking."
    Unknown: "The open points need experiment or discovery."
```

The `shared_session.*` keys sit under one `shared_session` object in the repository file and have
no user-config option. The interview's shared lane resolves them once, when it starts a session,
and writes them into that session's data folder; the server reads them only when it first creates
the session's state, so later edits reach new sessions, and a running session changes from its Host
view.
