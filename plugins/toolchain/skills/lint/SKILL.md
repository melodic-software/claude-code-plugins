---
name: lint
description: "Run polyglot linters and format checks across all affected ecosystems without a full build cycle — auto-detects ecosystems from changed files, honors each tool's config-file opt-in, and supports --fix mode to auto-correct where linters allow. Use for quick lint/format feedback during development; for build+test use /toolchain:check, for full outcome verification use /verification:confirm."
user-invocable: true
argument-hint: "[ecosystem] [--fix] (e.g., /toolchain:lint, /toolchain:lint dotnet, /toolchain:lint --fix, /toolchain:lint all)"
---

## Pre-computed context

Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "not a git repository"`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Run lint and format checks across affected ecosystems in one command. Fills the gap between "no check" and `/verification:confirm` (build+test+lint):

| Skill | What it runs | Speed |
|-------|-------------|-------|
| `/toolchain:lint` | Lint + format only | Fast (~5-15s) |
| `/toolchain:check` | Build + test + lint | Medium (~30-60s) |
| `/verification:confirm` | Build + test + lint + outcome verification | Medium+ |

Use `/toolchain:lint` for quick feedback during development. Use `/verification:confirm` before committing.

**The command surface is resolved, not hardcoded.** `/toolchain:lint` resolves each ecosystem's `check-cmd`/`fix-cmd` through the shared four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) — shared with `/toolchain:check`: the consuming repo's tracked `.claude/ecosystems/<ecosystem>.yaml` is authoritative when present; the plugin's bundled portable defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the rung-4 fallback. The consumer's file always wins.

## Arguments

`$ARGUMENTS` — optional ecosystem filter and/or mode flag.

**Ecosystem filters** (if omitted, auto-detect from changed files):

`/toolchain:lint` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `yaml`, and `cross-cutting` (each resolved per the ladder); any with matching files is exposed as a filter. Aliases: `py` → `python`; `ts`/`node` → `typescript`; `shell` → `bash`; `ps`/`pwsh` → `powershell`; `md` → `markdown`; `xc`/`text` → `cross-cutting`. Literal `all` runs every applicable ecosystem.

**Mode flag:**

| Flag | Effect |
|------|--------|
| (default) | Check mode — report violations, no file modifications |
| `--fix` or `fix` | Fix mode — auto-correct where the linter supports it |

**Combinable:** `/toolchain:lint dotnet --fix`, `/toolchain:lint --fix`, `/toolchain:lint all`, `/toolchain:lint md`

## Workflow

### 0. Resolve repo root and parse arguments

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Parse `$ARGUMENTS` for:

- **Ecosystem filter**: extract any ecosystem name. Default: auto-detect
- **Fix mode**: detect `--fix` or `fix` in arguments. Default: check mode

### 1. Detect ecosystems

If an ecosystem filter was provided, use it. If `all`, run every applicable ecosystem from the config. Otherwise, classify changed files from `git status --porcelain` against each ecosystem's `globs` list; when the working tree is clean, fall back to the branch diff so checkpoint-committed work still gets classified. Resolve the default branch by **detection, not assumption** — never a hardcoded `main`/`master` — and assign it before use:

```bash
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)}
if [[ -n "$DEFAULT_BRANCH" ]]; then
  git diff --name-only "$(git merge-base "$DEFAULT_BRANCH" HEAD)..HEAD"
else
  echo "branch diff unavailable (could not detect default branch)"
fi
```

If detection yields no default branch (no `origin/HEAD`, no upstream), skip the branch-diff path rather than guessing. A caller passing an explicit changed-file list (e.g. `/verification:confirm`) overrides both detection paths. Cross-cutting runs alongside detected ecosystems when ANY text file changed AND the repo opts into its tools.

Auto-detection algorithm:

1. Resolve each covered ecosystem's surface per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) (consumer `.claude/ecosystems/<ecosystem>.yaml` when present, else the bundled default; a malformed consumer file warns and degrades to inference, never a hard stop). Skip any ecosystem whose resolved `enabled` is `false` (a consumer opt-out) — excluded even under `all`
2. For each ecosystem, match its `globs` against the changed-files list
3. Run every ecosystem with ≥1 glob match whose `opt-in` condition holds, plus cross-cutting when any text file changed

If neither detection path yields changes and no filter specified: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:lint all` to check the full repo, or `/toolchain:lint <ecosystem>` for a specific filter." and stop.

### 2. Run linters per ecosystem

Run each ecosystem's resolved `check-cmd` (or `fix-cmd` with `--fix`). Honor each ecosystem's `opt-in` — skip tools the project hasn't configured.

For ecosystem-specific gotchas, reference `/toolchain:check` — its `context/<ecosystem>.md` files own the per-ecosystem prose detail.

Per-project walking (ecosystems with `project-discovery`):

- python: walk each `pyproject.toml` directory and run check/fix from there
- typescript: walk each `package.json` directory and run check/fix from there

Tool presence: verify tools on `PATH` before each ecosystem; report `skip` with `install-hint` when missing.

Tool pins (`tool-pin` sub-key, e.g. zizmor): when the resolved config pins a tool version, warn if the installed version drifts from the pin (a pin typically mirrors the consumer's own CI pin). No pin, no check.

Cross-cutting: resolve `$EC_BIN` for editorconfig-checker binary-name variants before substituting into the check command:

```bash
EC_BIN=""
if command -v ec >/dev/null 2>&1; then EC_BIN=ec
elif command -v editorconfig-checker >/dev/null 2>&1; then EC_BIN=editorconfig-checker
elif command -v ec-windows-amd64 >/dev/null 2>&1; then EC_BIN=ec-windows-amd64
fi
```

### 3. Present results

```text
## Lint Results

| Ecosystem  | Lint     | Format   | Status |
|------------|----------|----------|--------|
| dotnet     | pass     | pass     | PASS   |
| python     | FAIL     | pass     | FAIL   |
| bash       | pass     | pass     | PASS   |
| markdown   | pass     | —        | PASS   |

Overall: FAIL (1 of 4 ecosystems failed)
```

Use `pass`, `FAIL`, `skip` (tool not installed), or `—` (not applicable). Split lint and format into separate columns where the ecosystem has both (dotnet, python, bash). Use a single "Lint" column for ecosystems with only one tool (markdown, yaml, powershell).

If fix mode was used, note which ecosystems were auto-fixed vs which have no auto-fix.

Show failing output below the table — truncated to key error lines, not the full dump.

### 4. Fix mode note

When `--fix` is used, auto-fix capability is derived from the config: an ecosystem supports auto-fix when its `fix-cmd` is non-null. Report check-only ecosystems alongside fixes: "Fixed formatting in dotnet, python. ShellCheck violations require manual fix (2 issues)."

## Edge cases

- **No git changes but `/toolchain:lint all`**: run all applicable ecosystems (useful after rebase or pull)
- **Missing tools**: report as `skip` with tool name and install hint, not as failure
- **Multiple projects in same ecosystem**: run per-project (each `pyproject.toml`, each `package.json`)
- **File outside any ecosystem**: silently skip (no noise for binary files, images, etc.)
- **CWD drift**: always use absolute paths from `$REPO_ROOT`

## Relationship to other skills

- **Composes from `/toolchain:check`**: `/toolchain:check` owns the per-ecosystem prose gotchas — reference it rather than duplicating
- **Composed by `/verification:confirm`** (the separate `verification` plugin, when installed): the lint leg of full verification
- **After a simplify/cleanup pass**: run `/toolchain:lint` to catch formatting issues the cleanup introduced
- **Before commit**: `/toolchain:lint --fix` is a quick pre-commit cleanup without the overhead of a full build
