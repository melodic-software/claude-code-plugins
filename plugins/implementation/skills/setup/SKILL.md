---
name: setup
description: "Configure the implementation plugin for this repository: interview the user, infer per-ecosystem build/test/lint commands from the repo layout, write the tracked .claude/ecosystems/<ecosystem>.yaml files that /implementation:build and /implementation:lint resolve first, and offer the tracked .claude/topic-docs.yaml concern file that places plan and verification artifacts. Use when: 'set up implementation', 'configure build/lint commands', 'implementation setup', /build or /lint reports it is falling back to bundled defaults, a toolchain change needs recording, or a skill asks where topic documents should land. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "[ecosystem] (no arguments — interview every inferred ecosystem; or name one to (re)configure just that ecosystem)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Write (or update) the consuming repo's tracked ecosystem command surface at
`.claude/ecosystems/<ecosystem>.yaml` so `/implementation:build` and `/implementation:lint` resolve
commands deterministically from rung 1 of the ladder
([`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md))
instead of inferring or falling back to bundled defaults every run. This skill is the ladder's
**writer** for rungs 2 and 3 (infer-and-persist, ask-and-persist).

Idempotent: re-running reads the existing files and offers updates rather than overwriting blind.

## Task

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Write only inside `$REPO_ROOT/.claude/ecosystems/`. Never write into the plugin directory or the
plugin data directory — configuration lives in the consumer's tracked files.

### 1. Read existing config first

For each `$REPO_ROOT/.claude/ecosystems/<ecosystem>.yaml` that already exists, load it and present a
short summary (which ecosystems are configured, and each one's `build-cmd`/`test-cmd`/`check-cmd`/`fix-cmd`).
The interview proposes changes against that baseline; nothing is dropped without the user confirming.
If `$ARGUMENTS` names one ecosystem, scope the whole run to just that file.

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
- **yaml** — `.github/workflows/` present (lint-only surface — `/lint` runs it, `/build` does not).
- **cross-cutting** — repo-root config for `typos`/`gitleaks`/editorconfig-checker present (lint-only).

Repo-specific CI-parity gates beyond plain build/test/lint (lockfile drift, generated-artifact
freshness, schema regeneration) belong in the ecosystem file's `gates` array — draft one when the
repo's CI runs such a check.

### 3. Interview, one decision at a time

Present each inferred ecosystem's drafted command surface with a recommendation; let the user accept,
edit, or skip it. When inference is ambiguous (multiple test runners, no configured linter), ask for
the command rather than guessing. Offer any ecosystem the repo has that inference missed last.

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

The plugin's skills place plan progress, verification manifests, and baselines per the topic-docs
convention ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).
When `$REPO_ROOT/.claude/topic-docs.yaml` is absent, offer to write it — one question, recommended
option first (`contract_tier: branch`, the default; `local` for solo/offline work) — and materialize
only the keys that differ from the documented defaults, offering every schema key (`contract_dir`,
`memory_dir`, `contract_tier`, `vault_backend`). When it exists, leave it alone unless the user asks
to reconfigure — and preserve every schema key it carries; a re-run never drops one. Before writing, run the conflict check: `git check-ignore -v` on a
representative file path inside the contract root (e.g. `docs/topics/probe/PLAN.md`, or under the
chosen `contract_dir` — a bare directory misses `**` patterns) — a matching ignore rule is surfaced to
the user with the exact rule, never worked around. Never edit the consumer's root `.gitignore`; the
resolved memory root self-ignores through its own `.gitignore`.

## Output

Tracked `.claude/ecosystems/*.yaml` files in the consuming repo — plus `.claude/topic-docs.yaml`
when accepted — and a one-paragraph summary of what was written and how to re-run this setup to
reconfigure.

## What this skill does NOT do

- Run build/test/lint — that is `/implementation:build` and `/implementation:lint`.
- Write machine-local state — configuration lives in the consumer's tracked files, never in the plugin
  directory or the plugin data directory.
- Ship or edit the bundled portable defaults — those are the plugin's rung-4 fallback, never written
  into a consumer repo except as the seed for a file this interview produces.
