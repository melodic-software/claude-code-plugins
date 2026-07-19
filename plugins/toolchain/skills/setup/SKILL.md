---
name: setup
description: "Configure the toolchain plugin for this repository. check (read-only): report which ecosystems are configured, each one's resolved build/test/lint command surface, and the topic-docs concern file, validating the tracked files against the contract schema. apply: interview the user, infer per-ecosystem commands from the repo layout, and write the tracked .claude/ecosystems/<ecosystem>.yaml files that /toolchain:check and /toolchain:lint resolve first, plus the offered .claude/topic-docs.yaml concern file. Use when: 'set up toolchain', 'configure build/lint commands', 'toolchain setup', /toolchain:check or /toolchain:lint reports it is falling back to bundled defaults, a toolchain change needs recording, or a skill asks where topic documents should land. Actions: check (read-only verification, default) | apply (write the ecosystem command config and topic-docs concern file). Re-runnable and safe."
argument-hint: "check | apply [<ecosystem>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and configure the consuming repo's tracked ecosystem command surface per the uniform setup
contract: `check` reports what is configured, `apply` writes it. The tracked files at
`.claude/ecosystems/<ecosystem>.yaml` let `/toolchain:check` and `/toolchain:lint` resolve commands
deterministically from rung 1 of the ladder
([`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md))
instead of inferring or falling back to bundled defaults every run. This skill is the ladder's
**writer** for rungs 2 and 3 (infer-and-persist, ask-and-persist).

Idempotent: re-running reads the existing files and offers updates rather than overwriting blind. The
plugin ships working bundled portable defaults (rung 4), so an unconfigured ecosystem is **INFO** (the
default resolves), never FAIL.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then writes.
`apply <ecosystem>` scopes the whole run to that one ecosystem; when a named ecosystem's inference is
unambiguous it is written non-interactively, otherwise (or with no ecosystem argument in an
interactive session) the interview below runs.

### Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Read and write only inside `$REPO_ROOT/.claude/` — never the plugin directory or the plugin data
directory; configuration lives in the consumer's tracked files.

## `check` (read-only)

The bundled portable defaults and the contract schema are the single source of truth for the file
shape (`${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/`, `ecosystem.schema.json`). **Read the ladder
first**, then report a PASS/FAIL/INFO table; modify nothing.

1. **Configured ecosystems.** For each `$REPO_ROOT/.claude/ecosystems/<ecosystem>.yaml` present,
   report the ecosystem and its resolved command surface
   (`build-cmd`/`test-cmd`/`check-cmd`/`fix-cmd`). Validate each against the contract's
   `ecosystem.schema.json`. **FAIL** a schema-invalid file (with the validation error in the
   remediation line), or a tracked ecosystem file excluded by `.gitignore` (teammates would never
   receive it — report the matching rule). Otherwise PASS. If `$ARGUMENTS` names one ecosystem, scope
   the report to just that file.
2. **Unconfigured ecosystems.** INFO: detect which ecosystems the repo has that are *not* yet
   configured (see the inference signals under `apply`), and note that `/toolchain:check` /
   `/toolchain:lint` resolve those through inference then the bundled portable defaults. The
   remediation is `apply` to persist a command surface.
3. **Topic-docs concern file** (`$REPO_ROOT/.claude/topic-docs.yaml`). Report present/absent and, when
   present, the effective `contract_tier` and `vault_backend`. INFO when absent (companion plugins use
   the documented defaults). When `vault_backend` is `gitbook`, note it is deferred and non-writable
   (see `docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`) — the writable promotion target
   remains `docs`.

## `apply` (idempotent)

Run `check` first. Then write the accepted ecosystem files and, when accepted, the topic-docs concern
file. After each write, confirm the file is tracked (not gitignored) — re-run the `check` probe for
that path rather than trusting the write.

### 1. Read existing config first

For each `$REPO_ROOT/.claude/ecosystems/<ecosystem>.yaml` that already exists, load it and present a
short summary. The interview proposes changes against that baseline; nothing is dropped without the
user confirming. If `$ARGUMENTS` names one ecosystem, scope the whole run to just that file.

### 2. Infer candidates from the repo before asking

Detect which ecosystems apply from what actually exists, and draft each one's command surface. Seed
the draft from the bundled portable default at
[`${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/<ecosystem>.yaml`](${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/),
then specialize it to the repo:

- **dotnet** — `*.slnx`/`*.sln`/`*.csproj` present. Resolve the `anchor` (solution file at root, else
  nearest project). Note any repo-specific trap in `notes` (e.g. the xUnit v3 `--nologo` pin).
- **python** — `pyproject.toml`/`uv.lock`. Prefer `uv run …` when `uv.lock` exists, else plain
  `ruff`/`pytest`. Set `project-discovery` to the `pyproject.toml` roots.
- **typescript** — `package.json`/`tsconfig*.json`. Read the `scripts` block for the real `test-cmd`;
  pick `check-cmd`/`fix-cmd` from the configured linter (`biome.json` → Biome, eslint config → ESLint).
- **bash** / **powershell** — shell/PowerShell files present; keep the bundled check/fix commands
  unless the repo documents its own.
- **markdown** — a markdownlint config present.
- **yaml** — `.github/workflows/` present (lint-only surface — `/toolchain:lint` runs it,
  `/toolchain:check` does not).
- **cross-cutting** — repo-root config for `typos`/`gitleaks`/editorconfig-checker present (lint-only).

Repo-specific CI-parity gates beyond plain build/test/lint (lockfile drift, generated-artifact
freshness, schema regeneration) belong in the ecosystem file's `gates` array — draft one when the
repo's CI runs such a check.

### 3. Interview or write non-interactively

When `apply <ecosystem>` names one ecosystem and its inference is unambiguous, write the drafted
command surface non-interactively. Otherwise interview, one decision at a time: present each inferred
ecosystem's drafted command surface with a recommendation; let the user accept, edit, or skip it. When
inference is ambiguous (multiple test runners, no configured linter), ask for the command rather than
guessing. Offer any ecosystem the repo has that inference missed.

### 4. Write the files

Materialize one `$REPO_ROOT/.claude/ecosystems/<ecosystem>.yaml` per accepted ecosystem, conforming to
the contract's `ecosystem.schema.json`. Each file carries a one-line header comment citing the
contract, `globs` (required), the four command keys (`null` where a phase does not apply), and the
optional keys that apply (`anchor`, `project-discovery`, `opt-in`, `install-hint`, `gates`, `notes`).
Confirm each file is tracked, not ignored.

Recommend the consumer validate these in their own gate — a `check-jsonschema` hook or CI lane against
the contract schema catches typos the tolerant reader would otherwise ignore.

### 5. Offer the overlay convention

Personal per-key overrides go in `.claude/ecosystems/<ecosystem>.local.yaml`; a user-global base at
`~/.claude/ecosystems/<ecosystem>.yaml` is also honored. Layers resolve
user-global → team → local overlay, additively per key. Recommend the consumer add
`.claude/ecosystems/*.local.*` to `.gitignore` if not already covered.

### 6. Offer the topic-docs concern file

Companion lifecycle plugins — `implementation` (`/implementation:implement`) and `verification`
(`/verification:confirm`, `/verification:measure`) — place plan progress, verification manifests, and
baselines per the topic-docs convention
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). This
skill offers the shared consumer-side concern file those plugins resolve, independent of whether they
are installed today.
When `$REPO_ROOT/.claude/topic-docs.yaml` is absent, offer to write it — one question, recommended
option first (`contract_tier: branch`, the default; `local` for solo/offline work) — and materialize
only the keys that differ from the documented defaults (always at least one explicit key, e.g.
`contract_tier: branch` — a comment-only YAML document parses as null and fails the contract
schema's `type: object`), offering every schema key (`contract_dir`,
`memory_dir`, `contract_tier`, `vault_backend`). When it exists, leave it alone unless the user asks
to reconfigure — and preserve every schema key it carries; a re-run never drops one. Before writing, run the conflict check — only when the chosen
tier is `branch` (local mode has no committed tier to guard): `git check-ignore -v` on a
representative file path inside the chosen contract root (e.g. `<contract_dir>/probe/PLAN.md` — a
bare directory misses `**` patterns) — a matching ignore rule is surfaced to
the user with the exact rule, never worked around. Never edit the consumer's root `.gitignore`; the
resolved memory root self-ignores through its own `.gitignore`. Whenever the effective
`vault_backend` is (or becomes) `gitbook` — preserved from an existing file or chosen by the user
during this interview — report that GitBook is deferred and non-writable (see
`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`): the effective writable promotion
target remains `docs` until a later reviewed decision enables the backend. Do not configure or test a
GitBook API, MCP, or Git Sync writer; offer to replace the key with `docs` only if the user chooses
that change.

## Output

Tracked `.claude/ecosystems/*.yaml` files in the consuming repo — plus `.claude/topic-docs.yaml`
when accepted — and a one-paragraph summary of what was written and how to re-run this setup to
reconfigure. `check` alone reports the effective configuration and changes nothing.

## What this skill does NOT do

- Run build/test/lint — that is `/toolchain:check` and `/toolchain:lint`.
- Write machine-local state — configuration lives in the consumer's tracked files, never in the plugin
  directory or the plugin data directory.
- Ship or edit the bundled portable defaults — those are the plugin's rung-4 fallback, never written
  into a consumer repo except as the seed for a file this interview produces.
