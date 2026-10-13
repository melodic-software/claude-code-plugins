---
description: "Lint and format checks across changed ecosystems without a full build, honoring each tool's config-file opt-in; --fix formats only, --code-fix applies semantic lint autofixes behind a confirmation gate. Use when: 'lint this', 'run the linter', 'format check', 'fix the formatting', 'is this formatted right', 'run prettier/ruff/eslint', or for quick lint/format feedback during development. Build and test: /toolchain:check."
user-invocable: true
disable-model-invocation: false
argument-hint: "[ecosystem] [--fix|--code-fix] [--yes] [--dry-run] [--all-files]"
metadata:
  workflow-stage: verify
  summary: Polyglot lint and format checks without a full build
---

**Arguments.** `[ecosystem] [--fix|--code-fix] [--yes] [--dry-run] [--all-files]`. e.g., /toolchain:lint, /toolchain:lint dotnet, /toolchain:lint --fix, /toolchain:lint --code-fix --yes, /toolchain:lint all

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into one invocation, so a worktree-isolated session screens each git read on its own:

- Working tree status (empty = clean), `git status --porcelain | head -20`
- Current branch, `git branch --show-current`

Keep the bound in the pipe; a read-time cap bounds nothing. Treat a failure (not a repository, git unavailable) as an unknown value and carry on.

## Purpose

Lint and format checks only, across the affected ecosystems: use it for quick feedback during development. `/toolchain:check` adds build and test; use `/verification:confirm` before committing.

Commands are resolved, not hardcoded: `check-cmd`, `fix-cmd` and `code-fix-cmd` come from the four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md), shared with `/toolchain:check`. The consuming repo's tracked `.claude/ecosystems/<ecosystem>.yaml` always wins; the bundled defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the last-rung fallback.

**Two mutators, two gates.** Format-only and code-changing autofixes are separate keys and separate flags. Bare `--fix` must never run semantic lint autofixes (ruff `check --fix`, golangci-lint `--fix`, biome `check --write`, …).

## Arguments

**Ecosystem filters** (default: auto-detect from changed files): `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`, `yaml`, `cross-cutting`. Aliases: `py` → `python`; `ts`/`node` → `typescript`; `shell` → `bash`; `ps`/`pwsh` → `powershell`; `md` → `markdown`; `golang` → `go`; `xc`/`text` → `cross-cutting`. Literal `all` runs every applicable ecosystem.

**Mode flags:**

| Flag | Effect |
|------|--------|
| (default) | Check mode. Report violations, no file modifications |
| `--fix` or `fix` | **Format-only** fix mode. Run each ecosystem's non-null `fix-cmd` (whitespace / import layout / style). Does **not** run `code-fix-cmd`. |
| `--code-fix` | **Code-changing** fix mode. Run each ecosystem's non-null `code-fix-cmd` behind the [confirmation gate](#code-fix-confirmation-gate). Mutually exclusive with `--fix` in one invocation; if both appear, prefer `--code-fix` and note that `--fix` was ignored. |
| `--yes` / `-y` | Skip the interactive confirmation prompt for `--code-fix`. Required for non-interactive / headless `--code-fix` applies. Inert for check mode and for `--fix`. |
| `--dry-run` | With `--code-fix`: emit the plan (commands + scoped files) and **stop**. Mutate nothing. Implies the plan half of the confirmation gate. |
| `--all-files` | With `--code-fix`: allow applying when the scoped file count exceeds the [file-cap](#code-fix-scope-fence) (default 40). Without it, over-cap runs stop after the plan. |

Flags combine with a filter: `/toolchain:lint dotnet --fix`, `/toolchain:lint --code-fix --yes`.

## Workflow

### 0. Resolve repo root and parse arguments

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Parse `$ARGUMENTS` for the ecosystem filter, the fix mode (`--fix`/`fix` format-only, `--code-fix` code-changing, else check mode) and the `--code-fix` flags (`--yes`/`-y`, `--dry-run`, `--all-files`).

### 1. Detect ecosystems

With a filter, use it; with `all`, run every applicable ecosystem. Otherwise match the changed files from `git status --porcelain` against each ecosystem's `globs`. A caller's explicit changed-file list (e.g. from `/verification:confirm`) replaces detection. When the working tree is clean, fall back to the branch diff, so work already committed at green checkpoints still gets classified. Detect the default branch, never hardcode `main` or `master`, with this script as written:

```bash
REMOTE="" DEFAULT_BRANCH=""
TRACKED=$(git config "branch.$(git branch --show-current | tr -d '\r').remote" 2>/dev/null | tr -d '\r')
[[ "$TRACKED" == "." ]] && TRACKED=""
CANDIDATES=$( { [[ -n "$TRACKED" ]] && echo "$TRACKED"; git remote | grep -qx origin && echo origin; git remote; } | awk 'NF && !seen[\$0]++' )
while IFS= read -r CANDIDATE; do
  BRANCH=$(git symbolic-ref --short "refs/remotes/$CANDIDATE/HEAD" 2>/dev/null)
  BRANCH=${BRANCH#"$CANDIDATE/"}
  BRANCH=${BRANCH:-$(git ls-remote --symref --end-of-options "$CANDIDATE" HEAD 2>/dev/null | awk '/^ref:/{sub(/refs\/heads\//,"",\$2); print \$2; exit}')}
  if [[ -n "$BRANCH" ]] && git rev-parse --verify --quiet "refs/remotes/$CANDIDATE/$BRANCH" >/dev/null; then
    REMOTE=$CANDIDATE DEFAULT_BRANCH=$BRANCH
    break
  fi
done <<< "$CANDIDATES"
if [[ -n "$REMOTE" ]]; then
  git diff --name-only "$(git merge-base "refs/remotes/$REMOTE/$DEFAULT_BRANCH" HEAD)..HEAD"
else
  echo "branch diff unavailable (could not detect default branch)"
fi
```

It tries the remote the current branch tracks, then `origin`, then the rest, and accepts the first whose own `HEAD` names a default branch with a local tracking ref. When none does, skip the branch diff rather than guess.

Then:

1. Resolve each ecosystem's surface per the ladder. A malformed consumer file warns and degrades to inference, never a hard stop. Skip any ecosystem whose resolved `enabled` is `false`, even under `all`.
2. Run every ecosystem with at least one `globs` match whose `opt-in` holds, plus cross-cutting when any text file changed and the repo opts into its tools.
3. A single-condition `opt-in` (dotnet, python) that is unmet keeps the ecosystem out of the run but in the report as `skip (opt-in unmet: ...)`, never silently omitted (e.g. dotnet with no C#-relevant `.editorconfig`). A multi-condition `opt-in` bundled in one command string (bash's shellcheck-always/shfmt-conditional split; cross-cutting's per-tool config files) cannot be partly skipped: run the command whole and report its real output (the atomicity gotcha in `/toolchain:check`).

If neither detection path yields changes and no filter specified: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:lint all` to check the full repo, or `/toolchain:lint <ecosystem>` for a specific filter." and stop.

### 2. Run linters per ecosystem

**Command selection by mode:**

| Mode | Command key | Gate |
|------|-------------|------|
| check (default) | `check-cmd` | none (read-only) |
| `--fix` | `fix-cmd` | none beyond the flag (format-only by contract) |
| `--code-fix` | `code-fix-cmd` | [confirmation gate](#code-fix-confirmation-gate) + [scope fence](#code-fix-scope-fence) |

An unmet single-condition `opt-in` fills every column of that ecosystem's row with `skip (opt-in unmet: <condition, one short phrase>)`. It counts toward the ecosystem total, never toward the FAIL count. Per-ecosystem gotchas live in `/toolchain:check`'s `context/<ecosystem>.md` files.

**`<files>` substitution:** expand to the ecosystem-scoped changed-file list (paths relative to the execution root). Prefer this scoped list over whole-tree `.` / `./...` whenever the command string contains `<files>`. Under `/toolchain:lint all` with an empty detection set, expand to the matching files under each project root (or the repo root) rather than inventing a silent whole-tree rewrite for code-fix, and still apply the [file-cap](#code-fix-scope-fence) to that expanded set.

**Go `*.go` filter for format/code-fix:** ecosystem `globs` include `go.mod` / `go.sum`, but `gofmt -w` and `golangci-lint run --fix` reject non-source inputs (`gofmt` exits 2 on `go.mod`; `golangci-lint` requires named files in one directory). When substituting `<files>` into Go `format-cmd` / `code-fix-cmd`, drop every non-`.go` path first. For `golangci-lint run --fix`, further partition the remaining `.go` paths by parent directory and invoke once per directory (never pass a multi-directory file list in one process). If filtering leaves zero `.go` files, skip that Go format/code-fix command and report the skip rather than invoking the tool on module metadata alone.

**Per-project walking.** Run check and fix from each project root: every `pyproject.toml` directory (python), `package.json` directory (typescript) and `go.mod` directory (go; a root `./...` stops at a nested module boundary).

**Tool presence.** Before each ecosystem, check that the tool its commands are invoked through is on `PATH` (python's `uv`, not the `ruff` and `pyright` behind it). Missing: report `skip (tool missing: <tool>)` with `install-hint`, never `FAIL`. A sub-tool inside a compound command is not probed; its absence is a real non-zero exit and reports `FAIL`. This is the same rule as `/toolchain:check`, so both classify one environment the same way.

**Tool pins.** When the resolved config pins a tool version (`tool-pin`, e.g. zizmor), warn if the installed version drifts from the pin.

Cross-cutting: resolve `$EC_BIN` for editorconfig-checker binary-name variants before substituting into the check command:

```bash
EC_BIN=""
if command -v ec >/dev/null 2>&1; then EC_BIN=ec
elif command -v editorconfig-checker >/dev/null 2>&1; then EC_BIN=editorconfig-checker
elif command -v ec-windows-amd64 >/dev/null 2>&1; then EC_BIN=ec-windows-amd64
fi
```

### Code-fix confirmation gate

`--code-fix` changes semantics, not just whitespace, the only `/toolchain:lint` path that does. ALWAYS emit the plan first:

```text
Code-fix plan — ecosystems: <list> (<N> files scoped)
- python: uv run ruff check <files> --fix --no-unsafe-fixes --unfixable F401  (<n> files)
- go: golangci-lint run --fix <files>  (<m> files)
- typescript: (no code-fix-cmd) — skip
```

Then gate on session context and flags. Every side-effect path is explicitly gated, the gate never self-downgrades unattended:

| Session | Flags | Gate |
|---|---|---|
| Interactive | `--code-fix` only | Confirm with the user before applying. Honor scope narrowing ("only python"). |
| Interactive | `--code-fix --yes` | Skip the confirmation prompt and apply (still honor the file-cap unless `--all-files`). |
| Interactive or any | `--code-fix --dry-run` | Emit the plan and **STOP**. Mutate nothing. |
| Non-interactive (`CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop) | `--code-fix` without `--yes` | **STOP after the plan. Mutate nothing.** The plan IS the report. Re-run with `--yes` to apply. |
| Non-interactive | `--code-fix --yes` | Apply (still honor the file-cap unless `--all-files`). |

`--code-fix` opts INTO code-changing fix mode; `--yes` is the separate, explicit consent to mutate a tree with no human watching. A non-interactive session with no `--yes` is never consent. Bare `--fix` does not enter this gate.

### Code-fix scope fence

Before applying `--code-fix`:

1. **Changed-files allowlist.** Scope each `code-fix-cmd` to the ecosystem's changed-file list via `<files>` (or the expanded `all` set). Do not silently retarget a whole-tree `.` / `./...` when a non-empty scoped list exists.
2. **File cap (default 40).** Sum the scoped files across ecosystems that will actually run a non-null `code-fix-cmd`. If the sum exceeds 40 and `--all-files` is absent, emit the plan, report `file-cap exceeded (<count> > 40; pass --all-files to override)`, and **STOP**. Mutate nothing.
3. **No LOC auto-budget.** Do not invent a line-count ceiling; the confirmation plan (file list + commands) is the pre-apply review surface. After apply, surface `git diff --stat` so the operator can see blast radius.

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

Use `pass`, `FAIL`, a named skip, or `—` (not applicable). Skips use `/toolchain:check`'s named classes and block a "done" claim exactly as its report table says: `skip (tool missing: <tool>)` is an environment skip and blocks; `skip (opt-in unmet: <condition>)` does not. Lint installs nothing and runs no CI-parity gates, so it never emits `dependencies missing` or `unsupported`.

An ecosystem's Status and the Overall line read `FAIL` when any cell failed, `INCOMPLETE` when nothing failed but an environment skip remains, and `PASS` only when neither holds. `INCOMPLETE` names each cause with its reason (e.g. `Overall: INCOMPLETE (3 of 4 ecosystems passed; markdown: skip (tool missing: markdownlint-cli2))`), so a caller such as `/verification:confirm` holds its verdict on a lint-only environment gap. An opt-in-unmet skip or a `—` cell never makes a run `INCOMPLETE`.

Split Lint and Format into separate columns where the ecosystem has both (dotnet, python, bash); one Lint column otherwise (markdown, yaml, powershell). Show failing output below the table, cut to the key error lines.

After `--fix`, say which ecosystems were format-fixed and which have no `fix-cmd` ("Fixed formatting in dotnet, python, bash. markdownlint had no remaining auto-fixes."). After an applied `--code-fix`, say which ran `code-fix-cmd` and which have none, point format-only ecosystems at `--fix`, and show `git diff --stat`.

A consumer who still puts code-changing autofixes in `fix-cmd` keeps that behavior under `--fix` (their file wins); suggest moving them to `code-fix-cmd` so bare `--fix` stays format-only.

## Next

- Lint clean: /toolchain:check for build and test, then /verification:confirm before committing.
- Formatting failures only: /toolchain:lint --fix.

## Gotchas

- **Missing tool is never done.** `skip (tool missing: <tool>)` with the install hint makes the Overall line `INCOMPLETE`, not `FAIL` and not `PASS`.
- **`--code-fix` without `--yes` in a non-interactive session**, or over the file cap without `--all-files`: plan, then stop; never mutate.
- **Both `--fix` and `--code-fix`**: prefer `--code-fix`, note `--fix` ignored.
- **No git changes but `/toolchain:lint all`**: run all applicable ecosystems (useful after a rebase or pull).
- **File outside any ecosystem**: skip it silently.
- **CWD drift**: always use absolute paths from `$REPO_ROOT`.
