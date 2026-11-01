# Setup lifecycle: what a plugin's setup may write, and when

Owner doc for **what a plugin's `setup` skill may put in a consumer repository's always-loaded
instructions, and the lifecycle it follows**. One home per the
[convention registry](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#convention-registry);
skills point here and never restate the rules.

## Boundary

This doc owns the managed `AGENTS.md` block, its one-line-per-plugin ownership rule and the evidence
gate. It does not own:

- **The `setup` skill contract** (when a plugin needs one, the `check` and `apply` actions, what
  each must report). That is the
  [Setup is explicit and repeatable](../../plugin-philosophy.md#setup-is-explicit-and-repeatable)
  section of `docs/plugin-philosophy.md`, which this doc points at and does not restate.
- **Settings resolution and the convention home.** The
  [config-cascade contract](../config-cascade/README.md) and
  [ADR 0075](../../adr/0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
  own the layers, the pointer region and the invalid-value rule.
- **A user-level `~/.config/<plugin>/` layer.** There is none: ADR 0075 fix 9 retired the user-global
  file layer into `userConfig`.

## The managed block

The root `AGENTS.md` may carry one shared block:

```markdown
<!-- BEGIN GENERATED: plugin-conventions -->
- <one trigger line per plugin>
<!-- END GENERATED: plugin-conventions -->
```

- **One line per plugin.** Each plugin's setup owns exactly one line, found by a fixed prefix, and
  never edits any other byte. A line that only cites another plugin's skill belongs to that plugin.
  The user's text around the block is untouched.
- **Written after confirmation.** `apply` prints a diff and writes only after the operator confirms
  (or `--yes`). With no terminal and no `--yes`, it writes nothing.
- **Refuses what it cannot edit safely.** Unbalanced markers, a duplicate line for the plugin, a draft
  marker, or a symlinked `AGENTS.md` stop the write and report why.
- **Names only model-invocable skills.** A skill with `disable-model-invocation: true` is started by
  a person, so a line naming it spends context for nothing.
- **Shipped form.** `developer-experience` is the form that ships:
  `plugins/developer-experience/skills/setup/scripts/pointer-line.sh` (`check` and `apply`, states
  `current`, `stale`, `no-line`, `no-block`, `missing-file` and the refusals above).

## The evidence gate

A plugin's setup may add its line only with **that plugin's own stumble evidence**: the same failure
seen more than once against the current model, named where the line is added (PR body or an adjacent
comment). This is the Evidence-gated additions rule of
[Instruction economy](../../plugin-philosophy.md#instruction-economy) applied to the block.
Another plugin's evidence does not carry over, and anticipation of a failure a past model had is not
evidence. The line is an ablation candidate at each model release, like any standing instruction.
The decision is recorded in the amendment to ADR 0075 (2026-10-24).

## Verbs

A plugin whose setup writes a line offers `check` (read-only: reports the block, the line and whether
`AGENTS.md` reaches Claude Code's context) and `apply` (idempotent write). Their general contract is
the Setup section of `docs/plugin-philosophy.md`; the shipped example above shows the output and exit
codes.

## Sections later slices fill

A section below that still reads "Placeholder" is named so the slice that fills it has a place to
land (#6594, slices 2 to 4).

### Provenance

A setup settings file (`<home>/<plugin>.yaml`) records which plugin version wrote it and, per key,
whether the team chose the value. This lets `apply` tell a team choice from an inherited default
when a plugin changes a default. The shared writer, `lib/setup-apply.mjs`, records it for each
plugin whose entry point passes `provenance: true`. Each such plugin's schema declares both keys
beside `$schema`, and the writer refuses to record against a schema that does not, because a closed
schema would then reject the file it wrote:

```yaml
written_against: review@1.4.0
mode: strict
workers: 4
provenance:
  mode: chosen (default fast)
  workers: default
```

- **`written_against: <plugin>@<version>`** is the version in the plugin's
  `.claude-plugin/plugin.json`, rewritten at each write.
- **`provenance:`** holds one entry per scalar key the file sets. `default` marks a value filled at
  the plugin default (`--default <key>`). `chosen (default <d>)` marks one the operator set or
  confirmed, with `<d>` the plugin default at `written_against`. `chosen` alone marks a key with no
  default.
- **Values stay flat, and neither key is a setting.** `lib/parse-concern-value.sh` reads each
  schema key's value the same with or without these keys. `lib/config-cascade.mjs` skips both at
  the top level of every layer, so neither reaches `values`, a layer's errors or a userConfig name.
  `--check` prints no PASS line for them, and neither takes a `<key>=<value>`.
- **When `written_against` names another version**, `check` lists each `default` value that differs
  from the plugin default now (INFO). It also lists each `chosen` value whose recorded default
  differs, with its old and new default (WARN). A write with `--yes` sets each such `default` value
  to the plugin default and prints the change. It never changes a `chosen` value. A hand edit of a
  `default` value looks like a changed default, so set such a value as `<key>=<value>` to make it
  `chosen`. Each write records the current default in every `chosen` entry, so the WARN for a
  changed default prints up to and including the next write, and later `check` runs do not repeat it.
- **A file with no `provenance:` key** is read with every value `chosen`, and one INFO line says so.
- **A plugin version older than this record cannot read a file that holds it.** Its `--check` exits
  1 with no PASS line, and its `apply` refuses the file. Skills that read a setting through
  `--check` then drop the whole repository layer, so an enforced value such as `proof_level` or
  `downstream_probe` falls back to its default for that session. Everyone sharing a repository
  needs a version that declares both keys before one of them writes the file.
- **The writer owns both keys.** It rewrites the `provenance:` block whole, comments inside
  included. On a file that lacks them, it appends both keys after the last line, so only a new
  file has the order shown above.

Prose files keep their own markers: `developer-experience` writes `written_against` front matter
and a per-section `source=chosen|default` marker
(`plugins/developer-experience/skills/setup/reference/conventions-file.md`).

### Converge-by-state `apply`

`apply` acts on the state it finds rather than replaying steps. The shared writer,
`lib/setup-apply.mjs`, detects one of three states, and `--state` prints it as one line,
`<state> <path>`, with the path as its evidence, and writes nothing:

| State | Evidence | What a write does |
|---|---|---|
| `init` | No `<home>/<plugin>.yaml` and no retired file | Creates the file from the `<key>=<value>` and `--default` arguments. |
| `migrate` | The retired file is present | Carries every value from the retired file into `<home>/<plugin>.yaml`, then removes the retired file. |
| `configure` | `<home>/<plugin>.yaml` exists | Writes each key given over its line, or appends it. |

- **The retired file** is the one the plugin's
  [`retirements.yaml`](../retired-conventions/README.md#the-manifest-pluginspluginretirementsyaml)
  record names: the entry point passes the record id as `retired`, and the record must be an active
  `migrate` record of kind `file`. Detection is the record's own: a regular file at `path` whose
  content matches any `content_match`. A demoted (`report-only`) record never migrates. An entry
  point that names no record has only `init` and `configure`.
- **What is carried.** The top-level scalars of the retired file (a JSON object for a `.json`
  path, else the YAML subset), each with its [provenance](#provenance) entry. A value with no
  entry is carried as `chosen`. Each value goes through the same check as a `<key>=<value>`.
  The provenance rules apply against the retired file's `written_against`. A `default` value
  whose plugin default changed is carried at the new default, and the change is printed. A
  `chosen` value whose default changed is carried with the same WARN a write prints.
- **The new location wins.** A key that `<home>/<plugin>.yaml` or the command line already sets keeps
  that value. When both files exist, the run warns and names both paths.
- **Nothing is dropped silently.** A value it does not carry is printed: a key outside the
  schema, a value the schema does not allow, an empty key, a map or a list, or a value the new
  location sets differently. When any value is printed, the retired file stays in place. The retired file is
  removed only when every value in it is in `<home>/<plugin>.yaml` as written, and only after that
  file is written.
- **Confirmation.** A migration that would carry a value or remove the retired file needs `--yes`.
  Without it, the writer prints the plan and exits 3.
  `migrate` is the only state that runs with no `<key>=<value>`. In the other states a run with no
  key is a usage error (exit 2).
- **Idempotent.** A second run with the same inputs writes nothing.

### Current-facts check

A file a setup writes states only what is true of the repository now. A target, a change the team
wants that is not true yet, goes under a `## Not yet` heading in that file or into a work item,
never into a sentence that reads as fact: "every command accepts `--yes`" in a repository where one
command prompts with no bypass makes the next agent hang on that command.

`lib/check-convention-facts.mjs <file>...` is the shared, advisory check. It prints
`<file>:<line>: universal claim "<word>": <text>`, at most once per line, for each line outside
`## Not yet` with a sentence where `every`, `all`, `always`, `never` or `each` comes before more
words. It skips front matter, headings, code, HTML comments and sentences that open with "New" (a
rule for new work). It is a heuristic: it exits 0 whether or not it finds any and 2 on a usage
error or an unreadable file, and a finding is a statement to verify by reading the repository, not
proof that it is false. A plugin carries it as a copy generated by `scripts/sync-shared-copies.sh`; its
`setup` `check` runs the copy and still verifies every statement itself. `developer-experience` is
the first adopter (`plugins/developer-experience/skills/setup/SKILL.md`, check step 5).
