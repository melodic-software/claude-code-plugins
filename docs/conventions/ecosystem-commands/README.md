# Ecosystem Commands Convention

A versioned, marketplace-wide contract for how a consuming repository declares its per-ecosystem
build/test/lint command surface, and how plugins resolve it. The consumer tracks one YAML file per
ecosystem under `.claude/ecosystems/`; every plugin that needs to know "what command builds / tests /
lints `<ecosystem>` in this repo" reads those files instead of baking its own table.

This directory is the source of truth: `ecosystem.schema.json` (per-file schema), `CHANGELOG.md`
(version history), `examples/` (worked fixtures).

## Why this contract exists

Before it, the same command truth was encoded independently in at least three places across this
marketplace — the `toolchain` plugin's `/toolchain:check` reference table, its `/toolchain:lint` reference table
(already divergent from `/toolchain:check`'s), and the `review` `ecosystem-specialist` agent's inline
defaults — with no consumer-declared source any of them could defer to. The concern is cross-plugin
by demonstrated fact, so the contract lives here in marketplace conventions (the same reasoning as
`docs/conventions/hook-telemetry/`), not inside any one plugin.

## The two layers: canonical verb vs context binding

The contract covers exactly one layer and deliberately excludes the other:

- **Canonical verb — ONE concern, owned here.** Which tool and flags constitute "lint Python in this
  repo" (`uv run ruff check . --no-fix`). When the verb changes, every surface that runs it must
  change together; divergence is always a bug. The verb belongs in exactly one place per repo: the
  `.claude/ecosystems/<ecosystem>.yaml` file.
- **Context binding — SEVERAL concerns, owned elsewhere.** Which file set, when, with what wrapper:
  git hooks bind verbs to staged files (`{staged_files}` templating), CI binds them to the full
  solution with gate-specific flags, an agent binds them to a targeted project or single test.
  Bindings legitimately differ per surface and stay in that surface's own config (lefthook lanes, CI
  workflows), which should cite the ecosystem file for the canonical verb rather than treat their
  binding as a second source of truth.

Tooling design is the evidence for the split: lefthook's file templating and pre-commit's
staged-vs-`--all-files` modes exist precisely because the same literal command string is not correct
across contexts.

## File layout and resolution

One file per ecosystem, named by ecosystem identifier (lowercase kebab-case; the filename stem IS the
identifier):

```text
.claude/ecosystems/
  dotnet.yaml            # tracked — team truth
  dotnet.local.yaml      # gitignored — personal overlay
  python.yaml
  ...
~/.claude/ecosystems/
  dotnet.yaml            # optional user-global defaults (all repos on a machine)
```

Resolution per ecosystem, additive per key: **user-global → team file → local overlay**. A later
layer overrides earlier layers key-by-key and never replaces the base file wholesale (the same
resolution the extensibility contract specifies for tracked rich config, and the same
vendor-defaults-plus-drop-in-overrides shape the UAPI configuration-files specification
standardizes). Recommended consumer `.gitignore` line: `.claude/ecosystems/*.local.*`.

The drop-in folder form is deliberate: each ecosystem is an independent slice with its own lifecycle
— adding one is a new file, retiring one is a deletion, and a toolchain change is a single-file diff.

## Seam classification (recorded deviation)

Extensibility contract v2.1 seam 2 names tracked rich config by *plugin* (`.claude/<plugin>.md|yaml`
or `.claude/<plugin>/**`). This contract intentionally names the folder by **concern**
(`.claude/ecosystems/`) instead — a recorded PRECEDENT-EXTENSION, one increment past the folder form:

- The concern is consumed by more than one plugin (`implementation`, `review`, any future
  verification-adjacent plugin). Plugin-naming would couple every other consumer — and the consuming
  repo's tracked files — to one plugin's name.
- Plugin boundaries are the volatile axis (skills move between plugins across restructures); the
  concern name is the stable one. A plugin split must not force consumer repos to migrate config.

General rule this instance establishes: **when a tracked-config concern is consumed by more than one
plugin, name the folder by concern and record the contract in `docs/conventions/`** — see
`docs/MIGRATION-PLAYBOOK.md` "Extensibility contract v2.1".

The directory is `.claude/`-scoped but not Claude-walled: it is ordinary tracked YAML any agent or
script can read. Agent-agnostic discovery is satisfied by the consuming repo citing the path from its
own agent-neutral instructions (`AGENTS.md`), per the agents-md convention of routing command truth
by reference.

## Resolution ladder (plugin behavior)

Plugins resolve the command surface per the convention-resolution ladder
(`docs/MIGRATION-PLAYBOOK.md` "Convention-resolution ladder"):

1. `.claude/ecosystems/<ecosystem>.yaml` present → use it. It is authoritative.
2. Absent → infer from the repo's build files (solution files, `pyproject.toml`, `package.json`, …)
   and **persist the inference** by offering to write the file (the owning plugin's re-runnable
   `setup` action is the writer).
3. Cannot infer → ask the user; offer to persist.
4. Otherwise → the plugin's bundled portable defaults.

Bundled portable defaults are schema-conformant per-ecosystem files shipped inside the plugin and
used **only** at rung 4 — they are a fallback, never a peer source of truth, and a plugin never
writes them into a consumer repo without the setup interview or an inference to persist.

## Schema

Each `<ecosystem>.yaml` conforms to [`ecosystem.schema.json`](ecosystem.schema.json). Command values
are **opaque shell strings** — the contract does not parse, template, or interpret them beyond the
documented placeholders:

| Placeholder | Meaning |
|---|---|
| `<files>` | The changed-files list scoped to this ecosystem |
| `<solution-or-project-file>` | Resolved per the ecosystem's `anchor` |
| `<project-dir>` | Each per-project root discovered via `project-discovery` |
| `$REPO_ROOT` | Absolute repo root (`git rev-parse --show-toplevel`) |

Consumers are tolerant readers: unknown keys are inert, missing optional keys fall back to defaults.
Consuming repos SHOULD validate their files against the schema in their own gates (a
`check-jsonschema` hook or CI lane); plugins SHOULD fail soft — a malformed file degrades to rung 2
of the ladder with a warning, never a hard stop. Tolerant reading has a known edge: a misspelled
key (`check_cmd` for `check-cmd`) passes the default schema check as an inert unknown key — repos
that want typo protection run `check-jsonschema --no-additional-properties` in their gate.

## Task-runner deferral (recorded decision)

A task-runner verb SSOT (go-task / just / `lefthook run` wrappers) was evaluated and **deferred**:
today only one execution surface (the agent-side dispatcher) consumes the canonical verbs, hooks and
CI intentionally own divergent context bindings, and a runner adds a toolchain prerequisite without
removing the need for the declarative metadata (globs, anchors, install-hints) plugins reason over.

Because command values are opaque strings, later adoption is a mechanical value swap
(`check-cmd: 'task lint:python'` or `check-cmd: 'lefthook run lint-python'`) with zero schema change
— the demotion path is designed in.

**Revisit triggers** (either fires → re-evaluate):

- The same logical verb's command string is maintained across 3+ execution surfaces such that one
  command bump requires 3+ coordinated edits; or
- lefthook's `ai:` agent-settings key reaches stable AND the org's standards repo extends its managed
  lefthook components to cover agent invocation — in which case the runner is lefthook itself, not a
  new tool.

## Versioning

The schema carries the contract version (`CHANGELOG.md`). Additive schema changes bump minor;
breaking changes bump major, get a changelog entry with a migration note, and re-trigger the
consuming plugins' version bumps (the plugin `version` is the only update-delivery vehicle — see
`docs/MIGRATION-PLAYBOOK.md` "Version pinning and update delivery").
