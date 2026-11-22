# Ecosystem Commands Convention

A versioned, marketplace-wide contract for how a consuming repository declares its per-ecosystem
build/test/lint command surface, and how plugins resolve it. The consumer tracks one YAML file per
ecosystem under `docs/conventions/ecosystems/`; every plugin that needs to know "what command builds / tests /
lints `<ecosystem>` in this repo" reads those files instead of baking its own table.

This directory is the source of truth: `ecosystem.schema.json` (per-file schema), `CHANGELOG.md`
(version history), `examples/` (worked fixtures).

## Why this contract exists

Before it, the same command truth was encoded independently in at least three places across this
marketplace, in the `toolchain` plugin's `/toolchain:check` reference table, its `/toolchain:lint` reference table
(already divergent from `/toolchain:check`'s), and the `review` `ecosystem-specialist` agent's inline
defaults, with no consumer-declared source any of them could defer to. The concern is cross-plugin
by demonstrated fact, so the contract lives here in marketplace conventions (the same reasoning as
`docs/contracts/hook-telemetry/`), not inside any one plugin.

## The two layers: canonical verb vs context binding

The contract covers exactly one layer and deliberately excludes the other:

- **Canonical verb, one concern, owned here.** Which tool and flags constitute "lint Python in this
  repo" (`uv run ruff check . --no-fix`). When the verb changes, every surface that runs it must
  change together; divergence is always a bug. The verb belongs in exactly one place per repo: the
  `docs/conventions/ecosystems/<ecosystem>.yaml` file.
- **Context binding, several concerns, owned elsewhere.** Which file set, when, with what wrapper:
  git hooks bind verbs to staged files (`{staged_files}` templating), CI binds them to the full
  solution with gate-specific flags, an agent binds them to a targeted project or single test.
  Bindings legitimately differ per surface and stay in that surface's own config (lefthook lanes, CI
  workflows), which should cite the ecosystem file for the canonical verb rather than treat their
  binding as a second source of truth.

The split shows up in tooling design: lefthook's file templating and pre-commit's
staged-vs-`--all-files` modes exist precisely because the same literal command string is not correct
across contexts.

## File layout and resolution

One file per ecosystem, named by ecosystem identifier (lowercase kebab-case; the filename stem is the
identifier):

```text
docs/conventions/ecosystems/
  dotnet.yaml            # tracked, team truth
  dotnet.local.yaml      # gitignored, personal override
  python.yaml
  ...
~/.claude/ecosystems/
  dotnet.yaml            # optional user-global defaults (all repos on a machine)
```

Resolution per ecosystem, additive per key: **user-global → team file → personal override**. A later
layer overrides earlier layers key-by-key and never replaces the base file wholesale (the same
resolution the extensibility contract specifies for tracked rich config, and the same
vendor-defaults-plus-drop-in-overrides shape the UAPI configuration-files specification
standardizes). Recommended consumer `.gitignore` line: the recursive `docs/conventions/**/*.local.*`.

The drop-in folder form is deliberate because each ecosystem is an independent slice with its own lifecycle,
so adding one is a new file, retiring one is a deletion, and a toolchain change is a single-file diff.

## Location (recorded deviations)

The records live in the repository's convention home, beside every other plugin setting
([ADR 0064](../../adr/0064-home-plugin-customization-in-docs-conventions-yaml.md),
[ADR 0075](../../adr/0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)),
so any agent or tool reads them without reaching into one provider's folder. The folder is named by
**concern**, not by plugin: the concern is consumed by more than one plugin (`toolchain`, `review`,
`code-metrics`, `verification`), and plugin boundaries are the volatile axis.

Two deviations from the [config-cascade contract](../config-cascade/README.md) are declared here:

- **Folder form.** The cascade gives a new surface one `<home>/<concern>.yaml` file and no folder
  form. This surface keeps one file per ecosystem under `docs/conventions/ecosystems/`, for the
  drop-in reason above. The path is fixed at `docs/conventions/`, whatever home the repository
  binds.
- **User-global file.** The cascade has no user-global file layer and moves per-person values into
  `userConfig`. Readers still honor `~/.claude/ecosystems/<ecosystem>.yaml` until that layer
  migrates in its own change.

## Legacy location

Records used to live under `.claude/ecosystems/`. Until every repository holding records has moved
them, a reader that finds no team or personal file of a name under `docs/conventions/ecosystems/`
reads that file from `.claude/ecosystems/`, so a repository not yet moved keeps its commands. With a
file of the same name at both, the `docs/conventions/` file wins and the reader names both paths in
one warning. `/toolchain:setup apply` moves legacy files with `git mv`. The legacy read ends in the
next major version of this contract, released once that sweep is complete.

## Resolution ladder (plugin behavior)

Plugins resolve the command surface per the convention-resolution ladder
(`docs/migration-playbook.md` "Convention-resolution ladder"):

1. `docs/conventions/ecosystems/<ecosystem>.yaml` present (or its legacy file, per "Legacy
   location") → use it. It is authoritative.
2. Absent → infer from the repo's build files (solution files, `pyproject.toml`, `package.json`, …)
   and **persist the inference** by offering to write the file (the owning plugin's re-runnable
   `setup` action is the writer).
3. Cannot infer → ask the user; offer to persist.
4. Otherwise → the plugin's bundled portable defaults.

Bundled portable defaults are schema-conformant per-ecosystem files shipped inside the plugin and
used **only** at rung 4. They are a fallback, never a peer source of truth, and a plugin never
writes them into a consumer repo without the setup interview or an inference to persist.

## Schema

Each `<ecosystem>.yaml` conforms to [`ecosystem.schema.json`](ecosystem.schema.json). Command values
are **opaque shell strings**: the contract does not parse, template, or interpret them beyond the
documented placeholders:

| Placeholder | Meaning |
|---|---|
| `<files>` | The changed-files list scoped to this ecosystem |
| `<solution-or-project-file>` | Resolved per the ecosystem's `anchor` |
| `<project-dir>` | Each per-project root discovered via `project-discovery` |
| `$REPO_ROOT` | Absolute repo root (`git rev-parse --show-toplevel`) |

`fix-cmd` is **format-only** (whitespace / import layout / style). Semantic/code-changing
autofixes belong in optional `code-fix-cmd` and are invoked only by `/toolchain:lint --code-fix`
behind that skill's confirmation / `--yes` gate, never by bare `--fix`.

`lint-cmd` is the **report-only lint** command, kept apart from formatting: it changes no file and
checks no formatting. `check-cmd` keeps its meaning (a lint and format check) for existing records;
where `lint-cmd` is set, `/toolchain:lint` and `/toolchain:check` run it in place of `check-cmd`.
No hook runs a record's command: the format and lint plugins' batch rows and git-hook entries run
only the adapter each plugin ships, and `fix-cmd` and `lint-cmd` run when a person asks
`/toolchain:lint` or `/toolchain:check` (the
[check-placement convention](../check-placement/README.md), "Hooks run the shipped adapter").

`test-changed-cmd` is the **change-scoped test** command over `<files>`: it runs the tests the
changed files select, by the selection the repository's own test runner provides.
`/toolchain:check` runs it for a change and runs the full `test-cmd` under `all`, and when
`<files>` is empty. The repository's CI calls the same recorded command for a change-scoped run,
so an agent and CI select the same tests; the binding (which file set, which trigger) stays in
CI's own config. No bundled default sets it.

Consumers are tolerant readers: unknown keys are inert, missing optional keys fall back to defaults.
Consuming repos should validate their files against the schema in their own gates (a
`check-jsonschema` hook or CI lane); plugins should fail soft: a malformed file degrades to rung 2
of the ladder with a warning, never a hard stop. Tolerant reading has a known edge: a misspelled
key (`check_cmd` for `check-cmd`) passes the default schema check as an inert unknown key, so repos
that want typo protection run `check-jsonschema --no-additional-properties` in their gate.

### Gate execution scope

A `gates[]` item's `cmd` runs, by default (`run-from: ecosystem`, the implicit default when the key
is omitted), from the same location the ecosystem's own `build-cmd`/`test-cmd`/`check-cmd` use: once
per `project-discovery` root, the `anchor`'s directory, or `$REPO_ROOT` when the ecosystem defines
neither, unchanged from pre-`run-from` behavior. Set `run-from: repo-root` to force a single run
from `$REPO_ROOT` regardless of the ecosystem's `project-discovery` or `anchor`, for a repo-wide
check (protobuf generation, schema freshness) declared under a `project-discovery` ecosystem that
would otherwise run once per discovered project root, redundantly at best and failing in roots that
lack its config at worst. Under `run-from: repo-root`, a `cmd` using the `<files>` placeholder gets
the full ecosystem-scoped changed-files set (the same base definition the placeholder table above
gives), not one project's subset, because there is no single project root left to scope it to.

For the same reason, `<project-dir>` is **undefined** under `run-from: repo-root`: a single run has
no one project root to bind it to, and both plausible fallbacks, picking a root arbitrarily or
iterating them, contradict the single-run guarantee the key exists to give. A gate `cmd` that uses
`<project-dir>` while declaring `run-from: repo-root` is a configuration error; a resolver reports it
as a failure naming the gate and the unresolvable placeholder rather than guessing an expansion. Such
a gate is per-project by construction and belongs on the `ecosystem` default.

`run-from` is canonical-verb metadata, not a context binding: like `anchor`
and `project-discovery` (which already fix a gate's default execution location per repo), it is a
repo-invariant fact about *this* gate's `cmd` that every execution surface must agree on, not a
per-surface wrapper choice, so it belongs in the ecosystem file alongside them, not in a consuming
surface's own config.

### Command prerequisites

A resolver checks only that the tool a command is invoked through is on `PATH`. A command can need
more: a runtime package its script imports, or a tool at the build the repo pins for CI when the
host has another build under the same name. The optional `requires` key declares that, keyed by
command key, and a `gates[]` item carries its own `requires` list:

```yaml
check-cmd: "node tools/runner-policy.mjs && actionlint"
requires:
  check-cmd:
    - name: ajv
      probe: "test -f $REPO_ROOT/tools/node_modules/ajv/package.json"
      hint: "run npm ci in tools/"
    - name: actionlint (the build CI pins)
      probe: 'actionlint -version | head -n 1 | grep -qxF -f "$REPO_ROOT/.github/actionlint-version"'
      hint: "install the actionlint build named in .github/actionlint-version"
```

The `actionlint` probe matches the whole first line of `-version` output against the pin file, so
a missing or empty pin file reads absent rather than matching any build.

Each entry has a `name`, a `probe`, an optional `hint`, and an optional `run-from`: `repo-root`
(the default) or `ecosystem`, which probes from each location the command runs from and skips the
command only where the probe fails. A resolver applies them in this order:

1. The tool-presence check runs first; a missing tool reads `skip (tool missing: <tool>)` as before.
   An unmet single-condition `opt-in` then skips the command as before
   (`skip (opt-in unmet: <condition>)`), and its probes do not run.
2. Before the command runs, each of its entries' probes runs: one read-only command, from
   `$REPO_ROOT` unless the entry sets `run-from: ecosystem`. Exit 0 means present. Any other exit, a
   probe that cannot start, and one still running after 30 seconds all mean absent, never a failure.
3. With any entry absent, the command does not run. Its cell reads
   `skip (prerequisite missing: <name>)` with the entry's `hint`, an environment skip: the run's
   overall line reads `INCOMPLETE`, never `PASS`, and never `FAIL` for it. One absent entry skips
   the whole command, every tool bundled in its string included, since an opaque string cannot be
   partly run.
4. The run goes on to the next command and the next ecosystem.

A resolver compares no version or checksum: a record that needs one build of a tool writes a probe
that tells that build apart, against the pin the repo already keeps for CI. `tool-pin` stays a
drift warning. A resolver never installs a declared prerequisite, in any run; the `hint` is display
text it shows and never runs. Declaring a runtime package here, rather than installing it inside a
command string (an `npm ci` in `test-cmd`), keeps an unattended run from installing anything.

## Consumers

Execution consumers of the verb keys (`build-cmd`, `test-cmd`, `test-changed-cmd`, `check-cmd`, `lint-cmd`, `fix-cmd`,
`code-fix-cmd`) live under "Why this contract exists" (`toolchain:check`, `toolchain:lint`, the
`review` `ecosystem-specialist`). `verification:confirm` is an execution consumer only when the
`toolchain` plugin is not enabled: it then runs the project's build, test and lint commands itself,
taken from the project's `CLAUDE.md` and rules rather than the verb keys, and before each command
reads that command's `requires` (and a gate's own `requires`) from `docs/conventions/ecosystems/`, applying
the `opt-in`, `probe`, `run-from`, `name` and `hint` rules of "Command prerequisites"
(`plugins/verification/skills/confirm/SKILL.md:140`, `:144`). This table records plugins that read
lane membership without running a verb:

| Plugin | Keys | Use |
|---|---|---|
| `code-metrics` | `globs`, `enabled` only | `globs` replace the bundled extension map for that lane; a resolved `enabled: false` opts the lane out. No verb is run. An ecosystem file outside the supported YAML subset stops the run with exit 2 and `/code-metrics:setup check` shows FAIL, where this contract says plugins should fail soft. |

**Claim:** `code-metrics` consumes `globs` and `enabled` from `docs/conventions/ecosystems/<lane>.yaml` and
no other ecosystem-commands key. It diverges from the tolerant-reader paragraph above: an ecosystem
file outside the supported YAML subset stops the run with exit 2
(`plugins/code-metrics/scripts/resolve-config.py:467-472`) instead of failing soft. Parseable but
schema-invalid content is not validated. **Basis:** `plugins/code-metrics/reference/config.md` "Layers and
merge form", the paragraph on consumer ecosystems files. **Recheck:** when that paragraph names another key, or an audit skill starts running a verb from the ecosystem file.

## Task-runner deferral (recorded decision)

A task-runner verb SSOT (go-task / just / `lefthook run` wrappers) was evaluated and **deferred**:
today only one execution surface (the agent-side dispatcher) consumes the canonical verbs, hooks and
CI intentionally own divergent context bindings, and a runner adds a toolchain prerequisite without
removing the need for the declarative metadata (globs, anchors, install-hints) plugins reason over.

Because command values are opaque strings, later adoption is a mechanical value swap
(`check-cmd: 'task lint:python'` or `check-cmd: 'lefthook run lint-python'`) with zero schema
change. The demotion path is designed in.

**Recheck triggers** ([upstream-drift](../upstream-drift/README.md); either fires → re-evaluate):

- The same logical verb's command string is maintained across 3+ execution surfaces such that one
  command bump requires 3+ coordinated edits; or
- lefthook's `ai:` agent-settings key reaches stable and the org's standards repo extends its managed
  lefthook components to cover agent invocation, in which case the runner is lefthook itself, not a
  new tool.

## Versioning

The schema carries the contract version (`CHANGELOG.md`). Additive schema changes bump minor;
breaking changes bump major, get a changelog entry with a migration note, and re-trigger the
consuming plugins' version bumps (the plugin `version` is the only update-delivery vehicle, per
`docs/migration-playbook.md` "Version pinning and update delivery").
