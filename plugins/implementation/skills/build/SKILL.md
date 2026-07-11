---
name: build
description: "Run build, test, and lint verification for changed files, auto-detecting affected ecosystems (.NET, Python, TypeScript, Bash, PowerShell, Markdown) from git status, with the consuming project's own documented commands overriding portable defaults. Use after any code edit or for 'does it compile' / 'run tests' checks; for lint-only use /lint, for full outcome verification use /verify-changes."
user-invocable: true
argument-hint: "[ecosystem] (e.g., /implementation:build dotnet, /implementation:build python, /implementation:build all — default: auto-detect from git status)"
---

## Pre-computed context

Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo ""`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Single source of truth for ecosystem detection and build/test/lint CLI commands. Serves two roles:

1. **Task skill** — `/build` runs build verification for changed files. `/build dotnet` targets one ecosystem
2. **Reference skill** — sibling skills (`/verify-changes`, `/lint`) and any verification agents reference this for command tables instead of duplicating them

**Consumer conventions win.** When the consuming project documents its own build/test/lint commands (in its `CLAUDE.md`, rules, or a commands reference), use those instead of the defaults in [reference/ecosystem-config.md](reference/ecosystem-config.md).

## Arguments

`$ARGUMENTS` — optional ecosystem filter. If provided, run only that ecosystem. If omitted, auto-detect from changed files.

Available ecosystem filters come from the per-ecosystem config in [reference/ecosystem-config.md](reference/ecosystem-config.md); any ecosystem with `enabled: true` is exposed as a filter. Common aliases: `ts`/`node` → `typescript`, `shell` → `bash`, `ps`/`pwsh` → `powershell`, `md` → `markdown`. Literal `all` runs every enabled ecosystem.

## Ecosystem detection

Each enabled ecosystem in [reference/ecosystem-config.md](reference/ecosystem-config.md) declares a list of `globs` that classify changed files into that ecosystem. The skill matches `git status --porcelain` output against each ecosystem's `globs` to determine which ecosystems are affected.

For ecosystem-specific gotchas, reference files, and primary-source detail, read the corresponding context file:

- [context/dotnet.md](context/dotnet.md) — .NET build, test, format
- [context/sarif.md](context/sarif.md) — Roslyn SARIF output, jq parser patterns, AI consumption
- [context/python.md](context/python.md) — Python lint, format, test
- [context/typescript.md](context/typescript.md) — TypeScript compile, test, lint
- [context/bash.md](context/bash.md) — ShellCheck, shfmt
- [context/powershell.md](context/powershell.md) — PSScriptAnalyzer

When invoked as a task (`/build`), detect from `git status --porcelain`. When referenced by another skill, use the file list that skill provides.

## Workflow (when invoked as /build)

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

All commands use absolute paths. Never `cd` and lose context.

### 1. Detect ecosystems

If `$ARGUMENTS` specifies an ecosystem, use it. If `all`, run every enabled ecosystem. Otherwise, classify changed files from `git status --porcelain` against each enabled ecosystem's `globs` in [reference/ecosystem-config.md](reference/ecosystem-config.md).

If no changes detected and no `$ARGUMENTS`: report "No uncommitted changes found. Use `/build all` to verify the full repo, or `/build <ecosystem>` for a specific ecosystem." and exit.

**Conversation-aware targeting**: when the conversation has been working with specific files/projects, scope the build to what was touched — don't rebuild the whole scope for a single-project change. The ecosystem config's `anchor` field provides the default scoping anchor for ecosystems with a canonical entry point; substitute a narrower project file when changes are confined to one project. For .NET specifically: use the specific `.csproj` when changes are in one project, use the solution file when changes span multiple projects or touch shared files (`.props`, `.targets`, solution file).

### 2. Run checks

For each affected ecosystem, read the ecosystem config for that ecosystem's `build-cmd`, `test-cmd`, and `lint-cmd`. Null commands are skipped (no build step / no test framework / lint outsourced).

Substitute placeholders from the ecosystem config:

- `<solution-or-project-file>` ← resolved per the ecosystem's `anchor` description
- `<project-dir>` ← walked per-project root (driven by `project-discovery` patterns)
- `<files>` ← the changed-files list for that ecosystem

Run build → test → lint in order per ecosystem. Stop that ecosystem on first failure but continue to next ecosystem.

Tool presence: before each ecosystem runs, verify the tool is on `PATH`. If missing, report `skip` with the ecosystem's `install-hint` from the ecosystem config — never report `FAIL` for a missing tool.

**Project-declared CI-parity gates** — when the consuming project documents extra local checks that mirror CI gates plain build / test / lint don't catch (lockfile drift, generated-artifact freshness, schema regeneration), run the ones whose trigger files changed. These live in the consumer's own conventions (its `CLAUDE.md` / rules / commands reference) — this plugin ships none of its own.

For ecosystem-specific gotchas (xUnit `--nologo` trap, `dotnet test --project`, etc.), read the corresponding `context/<ecosystem>.md` file.

### 3. Report results

```text
## Build Results

| Ecosystem  | Build | Test | Lint | Status |
|------------|-------|------|------|--------|
| dotnet     | pass  | pass | pass | PASS   |
| python     | —     | pass | FAIL | FAIL   |

Overall: FAIL (1 of 2 ecosystems failed)
```

Use `pass`, `FAIL`, `skip`, or `—` (not applicable — for ecosystems where the corresponding command is null in the ecosystem config). Show failing command output below the table.

If any project-declared CI-parity gates fired, summarize each by name + outcome below the per-ecosystem block, with the remediation pointer on failure.

## For other skills referencing /build

When composing `/build` from another skill (like `/verify-changes` or `/lint`):

- **To get command tables**: read [reference/ecosystem-config.md](reference/ecosystem-config.md) (or the relevant `context/<ecosystem>.md` file for gotchas and prose detail)
- **To run full verification**: invoke `/build` or `/build <ecosystem>` via the Skill tool
- **To run lint-only checks**: invoke `/lint` or `/lint <ecosystem>` (the `/lint` skill maintains its own ecosystem command config)
- **To embed commands in agent prompts**: read [reference/ecosystem-config.md](reference/ecosystem-config.md) AND the corresponding `context/<ecosystem>.md` for gotchas

## Gotchas (cross-ecosystem)

- **CWD drift** — the #1 source of false failures. Always use absolute paths
- **Missing tools** — report as `skip` with reason, not as failure (e.g., `uv` not installed)
- **Multiple projects in same ecosystem** — ecosystems with an `anchor` use that as the scoping anchor; ecosystems with `project-discovery` patterns walk each discovered project root
