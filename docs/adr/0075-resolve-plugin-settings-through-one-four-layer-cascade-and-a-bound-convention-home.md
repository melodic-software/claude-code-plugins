# Resolve plugin settings through one four-layer cascade and a bound convention home

- Status: accepted; amended 2026-10-24 (the convention-home bullet on always-loaded content, see the amendment below)
- Date: 2026-10-18
- Supersedes: [ADR 0061](0061-adopt-a-five-layer-plugin-config-cascade-read-through-one-shared-resolver.md)
  for its layers and paths (the five-layer list, the user-global `~/docs/conventions/` layer and its
  "lower layer keeps the key" invalid-value rule);
  [ADR 0064](0064-home-plugin-customization-in-docs-conventions-yaml.md) Decisions 2 and 3 (the fixed
  `docs/conventions` root) and Decision 8 (its layer list);
  [ADR 0015](0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md) in full (the
  tracker binding at the repo root).
- Related: [ADR 0044](0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)
  (ADR 0064 Decision 2 carried its fixed root),
  [ADR 0018](0018-express-team-shared-conventions-as-consumer-convention-docs.md),
  [#7571](https://github.com/melodic-software/claude-code-plugins/issues/7571) (the thread),
  [#7104](https://github.com/melodic-software/claude-code-plugins/issues/7104) (records its
  invalid-value rule; the parser question stays open there),
  [#5906](https://github.com/melodic-software/claude-code-plugins/issues/5906) (records the homes its
  migration moves settings to; the migration stays there),
  [#6594](https://github.com/melodic-software/claude-code-plugins/issues/6594) (this ADR decides its
  layout question; its setup-lifecycle scope is not delivered here)

## Context

Three accepted records disagree about where a plugin setting lives and which layer wins. ADR 0061
adds a user-global file layer at `~/docs/conventions/` beside the contract's `~/.claude/<name>`, and
its invalid-value rule lets a lower layer keep the key. ADR 0064 fixes the root at
`docs/conventions`, so a repository that keeps its conventions elsewhere cannot bind a different
home. ADR 0015 binds the work-item tracker in a repo-root `.work-item-tracker.json`, outside every
convention the other plugins follow. A conventions vetting found fifteen gaps across these records
(absent pointer, symlinked instruction files, home-directory roots, monorepos, hooks in an unbound
repository, and others). One record has to say how every setting resolves, so the resolver and setup
code can be written once. This slice changes documents only.

## Decision

### Layers and precedence

Lowest first:

| Order | Layer | Source | Belongs to |
|---|---|---|---|
| 0 | plugin default | the plugin's bundled default | the plugin |
| 1 | `userConfig` | the plugin's `userConfig` option | the operator, per user |
| 2 | team | `<home>/<concern>.yaml`, and `<home>/<concern>.md` for prose | the repository, tracked |
| 3 | personal | `<home>/<concern>.local.<ext>` | one operator in one repository, gitignored |

- A higher layer beats a lower one key by key. The personal layer beats the team layer, except on a
  policy-floor key, where it may only tighten.
- There is no user-global file layer. `~/.claude/<name>` and ADR 0061's `~/docs/conventions/` move
  into `userConfig` (fix 9), so a per-person value has one channel.
- Instruction text beats config, and config beats plugin defaults. A skill that defers to an
  instruction says which file won. Instruction text never loosens a policy-floor key. Plugin
  defaults are fallbacks, and a skill never couples to this repository's own conventions.
- A prose overlay, `<home>/<concern>.local.md`, replaces whole team sections by heading.
- Every resolver reports which layer supplied each value.

### The policy-floor rule

A policy-floor key may only be tightened. The team layer sets the floor and the personal layer and
`userConfig` may move the value only in the key's floor direction. The seven fixed floors (D79,
T10-7, D96, D88, D100, Q131, the C13 intent gate) may only be tightened.

**`Floor direction` values.** The direction is a machine-readable column in the Implementers table of
[the config-cascade contract](../conventions/config-cascade/README.md), the one source of each
surface's direction. The shared resolver ships inside plugins and cannot read that README in a
consumer repository, so each caller passes its row's directions to the resolver as an option, as
`teamOnly` is passed today (resolver slice). The closed set of values, one per direction found on
`main` plus "no floor":

| Value | Meaning |
|---|---|
| `no-floor` | no key of the surface is a policy floor; the ordinary precedence applies |
| `team-only` | the team layer wins a direct conflict; a personal layer may add or tighten but never weaken |
| `lowest-value` | the lowest value across layers wins (a numeric ceiling) |
| `any-layer-wins` | the tightening value (`true`, or `report`) in any layer wins |
| `stricter-value` | the strictest value on the key's ordered scale across layers wins |

A cell holds one value, or several separated by commas when a surface has floor keys with different
directions. Each surface's keys and their scale stay in that surface's owner doc.

### The invalid-value rule

For every reader: name the file, key and value, and drop that layer. A valid higher layer still
wins, otherwise the default. A lower layer's value is never used. This is ADR 0064 Decision 7, kept,
and it settles #7104 item 1 against ADR 0061's "lower layer keeps the key".

### The convention home

- The default home is `docs/conventions/<concern>.md`, plus `<concern>.yaml` for model-free readers.
- The home is bound by the pointer region in the existing `AGENTS.md` or `CLAUDE.md`, and created
  when missing. Setup conforms to an existing equivalent home (for example a PascalCase
  `Documentation/`).
- YAML never goes under `.claude/`. There are no plugin-specific convention files and no
  `.work-item-tracker.json`.
- Guidance reaches consumers through the settings cascade. A setup action offers to write the
  convention files. Nothing is always-loaded, except the one evidence-gated trigger line the
  amendment below allows.

### Superseded and kept decisions

ADR 0064 Decisions 2 and 3 (the fixed root) and Decision 8 (its layer list) are superseded. Decisions
1, 5, 7 and 9 are kept (fix 3). Decisions 4 (existing surfaces migrate under #5906) and 6 (schema
home) stand: no decision here supersedes them. Codex and Cursor consumers get plugin defaults (fix
14); vendoring the resolver into codex-plugins and cursor-plugins is a later issue.

### The fifteen conventions-vetting fixes

1. **Three absences are separate.** No pointer region means ask once per repository (interactive) or
   escalate once per repository (lane). A pointer with no concern file means the bundled default,
   silently, reported as layer `default`. An absent key means the default. Only the first asks.
2. **The pointer region is the consent record.** Writing it means "use these defaults here". An
   optional `declined` line stops a declined repository from being asked again.
3. **Script-read settings are YAML.** Anything a script, hook, CI lane or policy floor reads is YAML
   at `<home>/<concern>.yaml`, schema-checked. Prose `.md` is only for model-read guidance with no
   floor. `scripts/check-convention-yaml.sh` reads the resolved home.
4. **`--ref` and stdin.** The resolver takes `--ref` (a 40-hex SHA or `origin/<name>`) and stdin,
   matching `parse-concern-value.sh`. Lanes resolve the pointer and read settings at the base SHA.
5. **Root classification.** The resolver classifies the root and returns "not applicable" when it is
   `$HOME`, an ancestor of it, or not inside a git work tree.
6. **Physical comparison.** `AGENTS.md` and `CLAUDE.md` are compared physically (`pwd -P` /
   `realpath`); there is no duplicate warning when one is a symlink to the other.
7. **Region placement.** The region is written where the repository already keeps instructions: the
   existing canonical file first. `AGENTS.md` is created only when neither exists.
8. **One overlay rule.** The personal overlay is `<home>/<concern>.local.<ext>`. Setup writes
   `<home>/**/*.local.*` to `.gitignore` in the same step that writes the pointer, announced, and
   rewrites it if the home moves. A prose overlay replaces whole team sections by heading.
9. **`userConfig` retires the user-global file.** The user-global layer (`~/.claude/<name>`) retires into
   `userConfig`, so per-person values have one channel.
10. **Unbound repositories.** Hooks use the bundled default plus a one-line notice when the repository
    is unbound. They fail closed only for a policy floor with no safe default.
11. **ADR 0015 is superseded.** The tracker binding moves to `<home>/work-items.yaml`,
    schema-checked, with a named YAML reader for Node and Python.
12. **This repository binds itself first.** The region goes in `AGENTS.md` and the resolver runs in
    CI. That edit is out of scope for the slice that lands this ADR (`AGENTS.md` is a protected
    path); a human PR does it.
13. **Monorepos.** One home per git root until a consumer asks. Hooks and lanes anchor the pointer
    read at the git toplevel, not `CLAUDE_PROJECT_DIR`.
14. **Codex and Cursor.** These consumers get plugin defaults; vendoring the resolver is a later
    issue.
15. **Foreign homes.** Inside a foreign home, our file names stay lowercase-kebab and are listed in an
    index file in the home, so the consumer can rename them under the pointer later.

### Settings for consumer differences (C17)

Where reasonable consumers differ, a preference becomes a setting with a named default, basis and
scope. Research depth for routine actions is a repository setting with the default "cite what is in
context". The values land with the threads that use them.

## Alternatives considered

- **Keep ADR 0061's five layers.** Rejected: two user-global paths (`~/.claude/<name>` and
  `~/docs/conventions/`) give a per-person value two channels, and `userConfig` already carries it.
- **Keep the fixed `docs/conventions` root.** Rejected: a repository with an equivalent home would
  keep two, and the pointer region already binds the prose home.
- **Keep the tracker binding at the repo root (ADR 0015).** Rejected: a one-off file outside the home
  contradicts fix 3 and the rule that no plugin has its own convention file.
- **Let a lower layer keep the key on an invalid value (ADR 0061).** Rejected: a value the team
  rejected would take effect from a layer further from the repository.

## Consequences

- ADR 0061, ADR 0064 and ADR 0015 each carry a status line that links this record.
- The config-cascade contract lists the four layers, the pointer region and the `Floor direction`
  column, and its `CHANGELOG.md` records a major `contract_version` bump, because the layer set and
  precedence change.
- The resolver, the setup writes and the per-surface migrations follow in their own slices. Until
  they land, a surface that still reads `~/.claude/<name>` or a `.claude/` overlay is a declared
  deviation from this contract, not a conformant one.
- #6594's fixed-YAML-path proposal is overruled by fix 3.

## Amendment (2026-10-24): one evidence-gated trigger line per plugin

The owner decided on 2026-10-24 (Q98, [#6594](https://github.com/melodic-software/claude-code-plugins/issues/6594))
that a plugin's setup may add one trigger line to the always-loaded root `AGENTS.md`, only with
stumble evidence that the plugin needs it. This replaces "nothing is always-loaded" in the convention
home section, and the same wording in the
[config-cascade contract](../conventions/config-cascade/README.md).

- **Where.** One line per plugin, inside the shared
  `<!-- BEGIN GENERATED: plugin-conventions -->` block of the root `AGENTS.md`. A plugin's setup owns
  its own line and no other byte of the block or the file.
- **How.** The plugin's setup writes the line after the operator confirms it. A plugin never writes it
  unasked.
- **What it names.** Only model-invokable skills. A skill with `disable-model-invocation: true` is
  not named, because the model cannot start it.
- **When.** Only with that plugin's own stumble evidence: the same failure seen more than once
  against the current model, named where the line is added (`docs/plugin-philosophy.md`, Instruction
  economy). Another plugin's evidence does not carry over, and anticipation is not evidence.
- **Shipped form.** The `developer-experience` block
  (`plugins/developer-experience/skills/setup/scripts/pointer-line.sh`) is kept as the form
  that ships, and the owner doc
  ([setup lifecycle](../conventions/setup-lifecycle/README.md)) records the rule.

The rest of the convention home section stands: topic conventions still live at the home and load on
demand, and the user-global file layer stays retired (fix 9).
