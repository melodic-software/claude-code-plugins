---
description: "Run polyglot linters and format checks across all affected ecosystems without a full build cycle. Auto-detects ecosystems from changed files, honors each tool's config-file opt-in, and supports --fix (format-only) plus a gated --code-fix mode for semantic lint autofixes. Use when: 'lint this', 'run the linter', 'format check', 'fix the formatting', 'is this formatted right', 'run prettier/ruff/eslint', or for quick lint/format feedback during development; for build+test use /toolchain:check, for full outcome verification use /verification:confirm."
user-invocable: true
disable-model-invocation: false
argument-hint: "[ecosystem] [--fix|--code-fix] [--yes] [--dry-run] [--all-files] (e.g., /toolchain:lint, /toolchain:lint dotnet, /toolchain:lint --fix, /toolchain:lint --code-fix --yes, /toolchain:lint all)"
shell: bash
metadata:
  workflow-stage: verify
  summary: Polyglot lint and format checks without a full build
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

**The command surface is resolved, not hardcoded.** `/toolchain:lint` resolves each ecosystem's `check-cmd`/`fix-cmd`/`code-fix-cmd` through the shared four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md). Shared with `/toolchain:check`: the consuming repo's tracked `.claude/ecosystems/<ecosystem>.yaml` is authoritative when present; the plugin's bundled portable defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the rung-4 fallback. The consumer's file always wins.

**Two mutators, two gates.** Format-only and code-changing autofixes are separate keys and separate flags. Bare `--fix` must never run semantic lint autofixes (ruff `check --fix`, golangci-lint `--fix`, biome `check --write`, …). That split matches the rest of the fleet's mutator pattern (`review:fanout fix` confirmation + `--yes`, `claude-memory:audit` never batch-applies without approval).

## Arguments

`$ARGUMENTS`, optional ecosystem filter and/or mode flags.

**Ecosystem filters** (if omitted, auto-detect from changed files):

`/toolchain:lint` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`, `yaml`, and `cross-cutting` (each resolved per the ladder); any with matching files is exposed as a filter. Aliases: `py` → `python`; `ts`/`node` → `typescript`; `shell` → `bash`; `ps`/`pwsh` → `powershell`; `md` → `markdown`; `golang` → `go`; `xc`/`text` → `cross-cutting`. Literal `all` runs every applicable ecosystem.

**Mode flags:**

| Flag | Effect |
|------|--------|
| (default) | Check mode. Report violations, no file modifications |
| `--fix` or `fix` | **Format-only** fix mode. Run each ecosystem's non-null `fix-cmd` (whitespace / import layout / style). Does **not** run `code-fix-cmd`. |
| `--code-fix` | **Code-changing** fix mode. Run each ecosystem's non-null `code-fix-cmd` behind the [confirmation gate](#code-fix-confirmation-gate). Mutually exclusive with `--fix` in one invocation; if both appear, prefer `--code-fix` and note that `--fix` was ignored. |
| `--yes` / `-y` | Skip the interactive confirmation prompt for `--code-fix`. Required for non-interactive / headless `--code-fix` applies. Inert for check mode and for `--fix`. |
| `--dry-run` | With `--code-fix`: emit the plan (commands + scoped files) and **stop**. Mutate nothing. Implies the plan half of the confirmation gate. |
| `--all-files` | With `--code-fix`: allow applying when the scoped file count exceeds the [file-cap](#code-fix-scope-fence) (default 40). Without it, over-cap runs stop after the plan. |

**Combinable:** `/toolchain:lint dotnet --fix`, `/toolchain:lint --fix`, `/toolchain:lint --code-fix`, `/toolchain:lint --code-fix --yes`, `/toolchain:lint all`, `/toolchain:lint md`

## Workflow

### 0. Resolve repo root and parse arguments

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Parse `$ARGUMENTS` for:

- **Ecosystem filter**: extract any ecosystem name. Default: auto-detect
- **Fix mode**: detect `--fix` / `fix` (format-only) vs `--code-fix` (code-changing). Default: check mode
- **Consent / scope flags**: `--yes` / `-y`, `--dry-run`, `--all-files` (only meaningful with `--code-fix`)

### 1. Detect ecosystems

If an ecosystem filter was provided, use it. If `all`, run every applicable ecosystem from the config. Otherwise, classify changed files from `git status --porcelain` against each ecosystem's `globs` list; when the working tree is clean, fall back to the branch diff so checkpoint-committed work still gets classified. Resolve the default branch by **detection, not assumption**, never a hardcoded `main`/`master`, and assign it before use:

```bash
REMOTE="" DEFAULT_BRANCH=""
TRACKED=$(git config "branch.$(git branch --show-current | tr -d '\r').remote" 2>/dev/null | tr -d '\r')
[[ "$TRACKED" == "." ]] && TRACKED=""
CANDIDATES=$( { [[ -n "$TRACKED" ]] && echo "$TRACKED"; git remote | grep -qx origin && echo origin; git remote; } | awk 'NF && !seen[$0]++' )
while IFS= read -r CANDIDATE; do
  BRANCH=$(git symbolic-ref --short "refs/remotes/$CANDIDATE/HEAD" 2>/dev/null)
  BRANCH=${BRANCH#"$CANDIDATE/"}
  BRANCH=${BRANCH:-$(git ls-remote --symref --end-of-options "$CANDIDATE" HEAD 2>/dev/null | awk '/^ref:/{sub(/refs\/heads\//,"",$2); print $2; exit}')}
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

The loop probes candidate remotes in priority order, the remote the current branch tracks (`branch.<name>.remote`) first, then `origin` if present, then the rest, and selects the first one whose default branch resolves to a locally available tracking ref, never a hardcoded remote name. This handles an unpushed feature branch (no tracking remote) in a repo cloned with a different remote name (e.g. `git clone -o vendor`), and skips a remote that was added but never fetched (its default branch has no local `refs/remotes/<remote>/<branch>` to diff against) in favor of a later remote that does, the candidate is accepted only when `git rev-parse` confirms the tracking ref exists locally. Each candidate's default branch comes from that remote's own `HEAD` (not the current branch's upstream, which on a pushed feature branch points at the feature branch itself and would make `merge-base` equal `HEAD`, yielding an empty diff), falling back to a `git ls-remote --symref` query when the local `HEAD` symref is absent. `merge-base` is taken against the fully-qualified remote-tracking ref `refs/remotes/$REMOTE/$DEFAULT_BRANCH`, which resolves without a local branch of that name and, like the `rev-parse` verify. Cannot be misparsed as an option when the remote name begins with a dash (`git clone --origin=-x`); the `git ls-remote` probe terminates option parsing with `--end-of-options` for the same reason. If no candidate yields a locally available default branch, skip the branch-diff path rather than guessing. A caller passing an explicit changed-file list (e.g. `/verification:confirm`) overrides both detection paths. Cross-cutting runs alongside detected ecosystems when ANY text file changed AND the repo opts into its tools.

Auto-detection algorithm:

1. Resolve each covered ecosystem's surface per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) (consumer `.claude/ecosystems/<ecosystem>.yaml` when present, else the bundled default; a malformed consumer file warns and degrades to inference, never a hard stop). Skip any ecosystem whose resolved `enabled` is `false` (a consumer opt-out). Excluded even under `all`
2. For each ecosystem, match its `globs` against the changed-files list
3. Run every ecosystem with ≥1 glob match whose `opt-in` condition holds, plus cross-cutting when any text file changed. This binary run/skip treatment applies cleanly when `opt-in` describes a SINGLE condition for the whole `check-cmd` (dotnet, python): unmet → excluded from the run but still reported (see sections 2 and 3 below, `skip (opt-in unmet: ...)`; never silently omitted). When `opt-in` instead describes MULTIPLE independent per-tool conditions bundled into one opaque command string (bash's shellcheck-always/shfmt-conditional split; cross-cutting's per-tool config-file list), this rule does not apply. `check-cmd`/`fix-cmd`/`code-fix-cmd` is a single opaque string with no way to run one sub-tool's portion without the other, so run it as before (unchanged from prior behavior) and report its real output. See `/toolchain:check`'s Gotchas for the known atomicity limitation this leaves open.

If neither detection path yields changes and no filter specified: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:lint all` to check the full repo, or `/toolchain:lint <ecosystem>` for a specific filter." and stop.

### 2. Run linters per ecosystem

**Command selection by mode:**

| Mode | Command key | Gate |
|------|-------------|------|
| check (default) | `check-cmd` | none (read-only) |
| `--fix` | `fix-cmd` | none beyond the flag (format-only by contract) |
| `--code-fix` | `code-fix-cmd` | [confirmation gate](#code-fix-confirmation-gate) + [scope fence](#code-fix-scope-fence) |

Honor each ecosystem's `opt-in`: for a single-condition ecosystem (dotnet, python), an unmet condition skips the whole ecosystem, reporting `skip (opt-in unmet: <condition, ≤10 words>)` visibly (never a silent omission) in every column that ecosystem's row has. This skip counts toward the table's total ecosystem count but never toward the FAIL count, the same precedent as a missing-tool skip. For a multi-tool ecosystem (bash, cross-cutting) whose `check-cmd` bundles multiple sub-tools into one opaque string, this binary treatment doesn't apply. Run and report `check-cmd`/`fix-cmd`/`code-fix-cmd` as before (unchanged from prior behavior); see `/toolchain:check`'s Gotchas for the known atomicity limitation.

For ecosystem-specific gotchas, reference `/toolchain:check`. Its `context/<ecosystem>.md` files own the per-ecosystem prose detail.

**`<files>` substitution:** expand to the ecosystem-scoped changed-file list (paths relative to the execution root). Prefer this scoped list over whole-tree `.` / `./...` whenever the command string contains `<files>`. Under `/toolchain:lint all` with an empty detection set, expand to the matching files under each project root (or the repo root) rather than inventing a silent whole-tree rewrite for code-fix, and still apply the [file-cap](#code-fix-scope-fence) to that expanded set.

**Go `*.go` filter for format/code-fix:** ecosystem `globs` include `go.mod` / `go.sum`, but `gofmt -w` and `golangci-lint run --fix` reject non-source inputs (`gofmt` exits 2 on `go.mod`; `golangci-lint` requires named files in one directory). When substituting `<files>` into Go `format-cmd` / `code-fix-cmd`, drop every non-`.go` path first. For `golangci-lint run --fix`, further partition the remaining `.go` paths by parent directory and invoke once per directory (never pass a multi-directory file list in one process). If filtering leaves zero `.go` files, skip that Go format/code-fix command and report the skip rather than invoking the tool on module metadata alone.

Per-project walking (ecosystems with `project-discovery`):

- python: walk each `pyproject.toml` directory and run check/fix from there
- typescript: walk each `package.json` directory and run check/fix from there
- go: walk each `go.mod` directory and run check/fix from there (a root `./...` invocation stops at a nested module boundary. See `/toolchain:check`'s per-ecosystem context file)

Tool presence: verify on `PATH` before each ecosystem the tool its commands are invoked through (python's `uv`, not the `ruff` and `pyright` behind it); report `skip` with `install-hint` when missing. The probe is per ecosystem, not per sub-tool: a sub-tool bundled inside an opaque compound `check-cmd` is not probed, so its absence surfaces at execution time as a real non-zero exit and the ecosystem reports `FAIL`, not `skip`. Same rule `/toolchain:check` states, so both skills classify an identical environment identically.

Tool pins (`tool-pin` sub-key, e.g. zizmor): when the resolved config pins a tool version, warn if the installed version drifts from the pin (a pin typically mirrors the consumer's own CI pin). No pin, no check.

Cross-cutting: resolve `$EC_BIN` for editorconfig-checker binary-name variants before substituting into the check command:

```bash
EC_BIN=""
if command -v ec >/dev/null 2>&1; then EC_BIN=ec
elif command -v editorconfig-checker >/dev/null 2>&1; then EC_BIN=editorconfig-checker
elif command -v ec-windows-amd64 >/dev/null 2>&1; then EC_BIN=ec-windows-amd64
fi
```

### Code-fix confirmation gate

`--code-fix` MUTATES semantics, not just whitespace, the only `/toolchain:lint` path that does. ALWAYS emit the plan first:

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

Use `pass`, `FAIL`, `skip` (tool not installed) or `skip (opt-in unmet: ...)` (config condition not met), or `—` (not applicable). Split lint and format into separate columns where the ecosystem has both (dotnet, python, bash). Use a single "Lint" column for ecosystems with only one tool (markdown, yaml, powershell). An opt-in-unmet skip fills every column that ecosystem's row has.

If `--fix` was used, note which ecosystems were format-fixed vs which have no `fix-cmd`.

If `--code-fix` was used (and applied), note which ecosystems ran `code-fix-cmd` vs which have none, and show `git diff --stat` for blast radius.

Show failing output below the table. Truncated to key error lines, not the full dump.

### 4. Fix mode notes

- **`--fix`:** auto-fix capability derives from a non-null `fix-cmd`. Report check-only ecosystems alongside format fixes: "Fixed formatting in dotnet, python, bash. markdownlint had no remaining auto-fixes."
- **`--code-fix`:** capability derives from a non-null `code-fix-cmd`. Ecosystems with only `fix-cmd` (format-only) are not code-fixed under this flag. Tell the operator to use `--fix` for those. Example: "Applied code-fix in python, go. typescript has no code-fix-cmd. Use `--fix` for format-only ecosystems (dotnet, bash, …)."

**Consumer overrides:** a consumer who still puts code-changing autofixes in `fix-cmd` keeps that behavior under `--fix` (their file wins). Prefer migrating those verbs into `code-fix-cmd` so bare `--fix` stays format-only. Bundled portable defaults already split the two.

## Edge cases

- **No git changes but `/toolchain:lint all`**: run all applicable ecosystems (useful after rebase or pull)
- **Missing tools**: report as `skip` with tool name and install hint, not as failure. Scoped to the tool the ecosystem's commands are invoked through, not every sub-tool a compound command reaches (an un-probed sub-tool's absence is a real non-zero exit, so `FAIL`; see `/toolchain:check`'s Gotchas)
- **Opt-in unmet**: report as `skip (opt-in unmet: ...)` with the condition, not as failure and not a silent omission (e.g., dotnet with no C#-relevant `.editorconfig`)
- **Multiple projects in same ecosystem**: run per-project (each `pyproject.toml`, each `package.json`)
- **File outside any ecosystem**: silently skip (no noise for binary files, images, etc.)
- **CWD drift**: always use absolute paths from `$REPO_ROOT`
- **`--code-fix` over file-cap without `--all-files`**: plan + stop, never mutate
- **`--code-fix` in non-interactive session without `--yes`**: plan + stop, never mutate
- **Both `--fix` and `--code-fix`**: prefer `--code-fix`, note `--fix` ignored

## Relationship to other skills

- **Composes from `/toolchain:check`**: `/toolchain:check` owns the per-ecosystem prose gotchas. Reference it rather than duplicating
- **Composed by `/verification:confirm`** (the separate `verification` plugin, when installed): the lint leg of full verification
- **After a simplify/cleanup pass**: run `/toolchain:lint` to catch formatting issues the cleanup introduced
- **Before commit**: `/toolchain:lint --fix` is a quick pre-commit **format** cleanup without the overhead of a full build. Use `/toolchain:lint --code-fix` (interactive confirm, or `--yes` when headless) only when you intentionally want semantic lint autofixes.
