# Ecosystem command resolution ladder

How `/toolchain:build` and `/toolchain:lint` resolve the per-ecosystem build/test/lint
command surface. Both skills read this one document; neither bakes its own table.

Implements the ecosystem-commands contract "Resolution ladder (plugin behavior)":
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/ecosystem-commands/README.md>.

## The command surface

Each ecosystem is one YAML file whose stem is the ecosystem identifier (lowercase kebab-case),
conforming to the contract's `ecosystem.schema.json`. Command keys are **opaque shell strings**:

- `build-cmd` — build/compile verification; `null` when the ecosystem has no build step
- `test-cmd` — test command; `null` when no test framework is wired
- `check-cmd` — lint/format check, no file modification; `null` when lint does not apply
- `fix-cmd` — auto-fix; `null` when the toolchain has no fix mode

Plus `globs` (required — classify changed files), and optional `enabled` (default `true`; a consumer
sets `false` to disable an ecosystem without deleting its file), `anchor`, `project-discovery`,
`opt-in`, `install-hint`, `tool-pin` (pinned tool versions keyed by tool name — the running skill
warns on installed-vs-pinned drift; inert when absent), `gates`, `notes`. Placeholders substituted by the running skill:
`<files>` (changed-files list scoped to this ecosystem), `<solution-or-project-file>` (resolved per
`anchor`), `<project-dir>` (each root from `project-discovery`), `$REPO_ROOT`
(`git rev-parse --show-toplevel`).

## Resolution per ecosystem (four rungs)

Resolve each ecosystem independently, in order; stop at the first rung that yields a command surface:

1. **Consumer file present → authoritative.** Read `.claude/ecosystems/<ecosystem>.yaml` in the
   consuming repo. Layer additively, **per key**, in this order — a later layer overrides earlier
   layers key-by-key and never replaces the base wholesale:
   `~/.claude/ecosystems/<ecosystem>.yaml` (user-global) → `.claude/ecosystems/<ecosystem>.yaml`
   (team) → `.claude/ecosystems/<ecosystem>.local.yaml` (personal overlay). Use the resolved values.
2. **Absent → infer, then offer to persist.** Infer the command surface from the repo's build files
   (solution files, `pyproject.toml`, `package.json`, …) and **offer to write** the inferred
   `.claude/ecosystems/<ecosystem>.yaml` via `/toolchain:setup` so the next run reads rung 1.
3. **Cannot infer → ask.** Ask the user for the command; offer to persist it via `/toolchain:setup`.
4. **Otherwise → bundled portable default.** Use the schema-conformant file shipped at
   [`${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/<ecosystem>.yaml`](ecosystems/). These are a
   **fallback only** — never a peer source of truth, and never written into a consumer repo outside
   the `/toolchain:setup` interview or a persisted inference.

**`enabled: false` → skip the ecosystem.** After resolution, an ecosystem whose resolved `enabled` is
`false` is not run — detection skips it and it is excluded even from `all`. This is the consumer's
opt-out; bundled defaults never set it. (A consumer overlay can also flip `enabled` back to `true`
per-key.)

**Malformed consumer file → warn and degrade to rung 2**, never a hard stop: surface the parse/schema
error, then infer as if the file were absent. (Consuming repos SHOULD validate their own files against
the schema in a gate; plugins fail soft.) Unknown keys are inert; missing optional keys fall back to
defaults.

## Setup writer

`/toolchain:setup` is the re-runnable writer for rungs 2 and 3 — it interviews, infers, and writes
`.claude/ecosystems/*.yaml` into the consuming repo. Recommend the consumer add
`.claude/ecosystems/*.local.*` to `.gitignore`.
