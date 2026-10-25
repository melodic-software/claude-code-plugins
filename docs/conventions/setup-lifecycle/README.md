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

Each section below is a placeholder, named so the slice that fills it has a place to land (#6594,
slices 2 to 4).

### Provenance

Placeholder, filled by slice 2: how a written line records which plugin and version wrote it.

### Converge-by-state `apply`

Placeholder, filled by slice 3: `apply` converges on the observed state rather than replaying steps.

### Current-facts check

Placeholder, filled by slice 4: `check` verifies that what the line says is still true.
