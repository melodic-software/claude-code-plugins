# Ecosystem command resolution ladder

How `/toolchain:check` and `/toolchain:lint` resolve the per-ecosystem build/test/lint
command surface. Both skills read this one document; neither bakes its own table.

Implements the ecosystem-commands contract "Resolution ladder (plugin behavior)":
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/ecosystem-commands/README.md>.

## The command surface

Each ecosystem is one YAML file whose stem is the ecosystem identifier (lowercase kebab-case),
conforming to the contract's `ecosystem.schema.json`. Command keys are **opaque shell strings**:

- `build-cmd`: build/compile verification; `null` when the ecosystem has no build step
- `test-cmd`: test command; `null` when no test framework is wired
- `check-cmd`: lint/format check, no file modification; `null` when lint does not apply
- `fix-cmd`: **format-only** auto-fix (whitespace / import layout / style); `null` when absent.
  Must not apply semantic/code-changing lint autofixes. `/toolchain:lint --fix` runs this key.
- `code-fix-cmd`: **code-changing** auto-fix (lint autofixes that rewrite logic, delete unused
  imports, apply safe/unsafe code edits); `null` when absent. `/toolchain:lint --code-fix` runs
  this key behind that skill's confirmation / `--yes` gate, never bare `--fix`.

Plus `globs` (required, classifies changed files), and optional `enabled` (default `true`; a consumer
sets `false` to disable an ecosystem without deleting its file), `anchor`, `project-discovery`,
`opt-in`, `install-hint`, `tool-pin` (pinned tool versions keyed by tool name, with the running skill
warning on installed-vs-pinned drift; inert when absent), `requires` (per command key, what the command
needs beyond its tool on `PATH`, each entry a `name`, a read-only `probe`, an optional `hint` and an optional `run-from`;
`/toolchain:check`'s "Declared prerequisites" says how both skills apply it), `gates`, `notes`. Placeholders substituted by the running skill:
`<files>` (changed-files list scoped to this ecosystem), `<solution-or-project-file>` (resolved per
`anchor`), `<project-dir>` (each root from `project-discovery`), `$REPO_ROOT`
(`git rev-parse --show-toplevel`).

## Covered ecosystems

No closed list decides which ecosystem ids a run accepts. An id is **covered** when any of these
holds:

- **Recorded.** A `<id>.yaml` or `<id>.local.yaml` exists at any rung-1 layer (user-global, team
  or personal override), whatever the id.
- **Inferred this run.** Rung 2 inferred a command surface for the id from the repo's build files
  in this run. The report names each inferred id with the globs inferred for it, on one line per
  id: `Inferred <id>: globs <glob>, <glob>`.
- **Bundled.** A bundled portable default ships for the id.

Before detection, `all` or an ecosystem filter, look for build files of ecosystems that are neither
recorded nor bundled (a `Cargo.toml`, a `Gemfile`, a `pom.xml`) and run rung 2 for each id they
point to, so an inferred id joins the set before any glob is matched or any filter is checked.
Detection, `all`, an ecosystem filter and the files-outside-every-ecosystem rule all read this set.
An unattended run takes only the id and its globs from this pass, offers nothing, and resolves the
id's commands by "Unattended runs" below.

A filter naming an id that is still not covered after that pass goes to rung 3: ask for its command and offer
`/toolchain:setup` to record it. With nobody to ask, run nothing for it and report
`<id>: no record and nothing to infer it from`.

## Resolution per ecosystem (four rungs)

Resolve each ecosystem independently, in order; stop at the first rung that yields a command surface:

1. **Consumer file present → authoritative.** Read `.claude/ecosystems/<ecosystem>.yaml` in the
   consuming repo. Layer additively, **per key**, in this order. A later layer overrides earlier
   layers key-by-key and never replaces the base wholesale:
   `~/.claude/ecosystems/<ecosystem>.yaml` (user-global) → `.claude/ecosystems/<ecosystem>.yaml`
   (team) → `.claude/ecosystems/<ecosystem>.local.yaml` (personal override). Use the resolved values.
2. **Absent → infer, then offer to persist.** Infer the command surface from the repo's build files
   (solution files, `pyproject.toml`, `package.json`, …) and **offer to write** the inferred
   `.claude/ecosystems/<ecosystem>.yaml` via `/toolchain:setup` so the next run reads rung 1.
3. **Cannot infer → ask.** Ask the user for the command; offer to persist it via `/toolchain:setup`.
4. **Otherwise → bundled portable default.** Use the schema-conformant file shipped at
   [`${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/<ecosystem>.yaml`](ecosystems/). These are a
   **fallback only**, never a peer source of truth, and never written into a consumer repo outside
   the `/toolchain:setup` interview or a persisted inference.

**`enabled: false` → skip the ecosystem.** After resolution, an ecosystem whose resolved `enabled` is
`false` is not run. Detection skips it and it is excluded even from `all`. This is the consumer's
opt-out; bundled defaults never set it. (A later layer can also flip `enabled` back to `true`
per-key.)

**Malformed consumer file → warn and degrade to rung 2**, never a hard stop: surface the parse/schema
error, then infer as if the file were absent. (Consuming repos should validate their own files against
the schema in a gate; plugins fail soft.) Unknown keys are inert; missing optional keys fall back to
defaults.

## Run kind

Decide it once, before the first read, and stop at the first check that holds (the
ecosystem-resolution contract's detector:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/ecosystem-resolution/README.md>):

1. The invocation says it is unattended: an `--unattended` argument, `CLAUDE_CODE_REMOTE` set,
   `claude -p`, a scheduled, loop or CI lane, or a subagent an unattended run dispatched. The run
   is unattended.
2. A person is in the session and can answer a question now. The run is attended.
3. Otherwise the run is unattended. A run that cannot tell counts as unattended.

An attended run uses the four rungs above. An unattended run uses the next section in their place.

## Unattended runs

An unattended run resolves each command it would run (`build-cmd`, `test-cmd`, `check-cmd`,
`lint-cmd`, `fix-cmd`, `code-fix-cmd`, and each `gates[]` item's `cmd`) from these sources only,
in this order, stopping at the first that yields it:

1. **Recorded.** Rung 1's layered record. A recorded `null` is resolved: the cell reads as not applicable.
2. **Stated.** The repository's own instructions (`CLAUDE.md`, an `AGENTS.md`, a `.claude/rules/`
   file, `CONTRIBUTING.md`) name the command for that ecosystem and key.
3. **Inferred.** The repository's files imply exactly one command, and only of these shapes, run
   as found with no flag added: a manifest script (`package.json` `scripts.test`, run through the
   package manager its lockfile names, `npm` with no lockfile), a task-runner target (a `Makefile`
   target, a `justfile` recipe), or the build tool's own verb on a named entry point
   (`dotnet build Cart.sln`, `cargo build` beside the one `Cargo.toml`).

Nothing else supplies a command. An unattended run never asks (rung 3), never runs a bundled
default's command or gate (rung 4), and copies no command text out of a CI workflow file. A bundled
default still supplies its `globs`, so a changed file reaches its ecosystem's row; none of its other
keys apply, a key it sets to `null` included. A malformed record degrades to the stated and
inferred sources.

- **Log each command as assumed.** Before a resolved command runs, print one line for it:
  `assumed: <ecosystem>.<key>=<command> (<file>:<line>)`, naming the record line, the stating line
  or the implying line. Repeat every `assumed:` line below the report's table.
- **Report what stays unresolved.** A key no source resolved does not run, and nothing runs in its
  place. Its cell reads `skip (unresolved: <ecosystem>.<key>)`, an environment skip that leaves the
  run `INCOMPLETE`, with one line below the table naming the files read. A gate only the bundled
  default ships does not run: it is listed on the `Gates:` line with
  `skip (unresolved: <ecosystem>.gates)`.
- **A tie is unresolved.** Two or more candidates for one key with nothing in the repository to
  choose between them: run none, report the key's cell as unresolved, and name every candidate with
  its file below the table.
- **Install nothing, write nothing.** Install no dependency or tool, write no
  `.claude/ecosystems/` file, and offer no `/toolchain:setup` persist. To make the next unattended
  run resolve a key, a person records it with `/toolchain:setup apply <ecosystem>`, or merges a
  lane's record pull request.

## Setup writer

`/toolchain:setup` is the re-runnable writer for rungs 2 and 3. It interviews, infers, and writes
`.claude/ecosystems/*.yaml` into the consuming repo. Recommend the consumer add
the recursive `.claude/**/*.local.*` line to `.gitignore`.
