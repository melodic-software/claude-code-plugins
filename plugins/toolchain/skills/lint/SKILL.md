---
description: "Lint and format checks across changed ecosystems without a full build, honoring each tool's config-file opt-in; --fix formats only, --code-fix applies semantic lint autofixes behind a confirmation gate. Use when: 'lint this', 'run the linter', 'format check', 'fix the formatting', 'is this formatted right', 'run prettier/ruff/eslint', or for quick lint/format feedback during development. Build and test: /toolchain:check."
user-invocable: true
disable-model-invocation: false
argument-hint: "[ecosystem] [--fix|--code-fix] [--yes] [--dry-run] [--all-files] [--unattended]"
metadata:
  workflow-stage: verify
  summary: Polyglot lint and format checks without a full build
---

**Arguments.** `[ecosystem] [--fix|--code-fix] [--yes] [--dry-run] [--all-files] [--unattended]`. e.g., /toolchain:lint, /toolchain:lint dotnet, /toolchain:lint --fix, /toolchain:lint --code-fix --yes, /toolchain:lint all, /toolchain:lint --unattended

## Repository context. Gather first

<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->
Run each command below as its own Bash call, all sent together in one message ([worktree isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)).
Keep any bound in the command's own pipe ([output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
<!-- END GENERATED: gather-block -->

- Working tree status (empty = clean), `git status --porcelain | head -20`
- Current branch, `git branch --show-current`

## Purpose

Run lint and format checks across affected ecosystems in one command. Fills the gap between "no check" and `/verification:confirm` (build+test+lint):

| Skill | What it runs | Speed |
|-------|-------------|-------|
| `/toolchain:lint` | Lint + format only | Fast (~5-15s) |
| `/toolchain:check` | Build + test + lint | Medium (~30-60s) |
| `/verification:confirm` | Build + test + lint + outcome verification | Medium+ |

Use `/toolchain:lint` for quick feedback during development. Use `/verification:confirm` before committing.

**The command surface is resolved, not hardcoded.** `/toolchain:lint` resolves each ecosystem's `lint-cmd`/`check-cmd`/`fix-cmd`/`code-fix-cmd` through the shared three-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md). Shared with `/toolchain:check`: the consuming repo's tracked `docs/conventions/ecosystems/<ecosystem>.yaml` (or the legacy `.claude/ecosystems/` file for a name absent there) is authoritative when present, then inference from its build files, then asking. The plugin ships no default command: a key nothing resolves is reported unresolved and runs nothing.

**The secret scan is lint's own.** It runs from this skill, not from a record, under its own opt-in, in attended and unattended runs alike: see [Secret scan](#secret-scan). Any other scan, a workflow-security scan included, runs only from a command the ladder resolves.

**Two mutators, two gates.** Format-only and code-changing autofixes are separate keys and separate flags. Bare `--fix` must never run semantic lint autofixes (ruff `check --fix`, golangci-lint `--fix`, biome `check --write`, …).

## Arguments

`$ARGUMENTS`, optional ecosystem filter and/or mode flags.

**Ecosystem filters** (if omitted, auto-detect from changed files):

`/toolchain:lint` accepts any covered ecosystem id, meaning one recorded, stated or inferred this run ([resolution ladder](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) "Covered ecosystems"), each resolved per the ladder. A consumer record such as `docs/conventions/ecosystems/rust.yaml` makes `rust` a filter. Aliases: `py` → `python`; `ts`/`node` → `typescript`; `shell` → `bash`; `ps`/`pwsh` → `powershell`; `md` → `markdown`; `golang` → `go`; `xc`/`text` → `cross-cutting`. Literal `all` runs every applicable ecosystem.

**Mode flags:**

| Flag | Effect |
|------|--------|
| (default) | Check mode. Report violations, no file modifications |
| `--fix` or `fix` | **Format-only** fix mode. Run each ecosystem's non-null `fix-cmd` (whitespace / import layout / style). Does **not** run `code-fix-cmd`. |
| `--code-fix` | **Code-changing** fix mode. Run each ecosystem's non-null `code-fix-cmd` behind the [confirmation gate](#code-fix-confirmation-gate). Mutually exclusive with `--fix` in one invocation; if both appear, prefer `--code-fix` and note that `--fix` was ignored. |
| `--yes` / `-y` | Skip the interactive confirmation prompt for `--code-fix`. Required for non-interactive / headless `--code-fix` applies. Inert for check mode and for `--fix`. |
| `--dry-run` | With `--code-fix`: emit the plan (commands + scoped files) and **stop**. Mutate nothing. Implies the plan half of the confirmation gate. |
| `--all-files` | With `--code-fix`: allow applying when the scoped file count exceeds the [file-cap](#code-fix-scope-fence) (default 40). Without it, over-cap runs stop after the plan. |
| `--unattended` | Marks the run unattended. A run without it is still unattended when the ladder's "Run kind" says so, including one that cannot tell whether a person is present. An unattended run resolves commands by the ladder's "Unattended runs": only a recorded, stated or inferred command runs, each logged `assumed:` with its source; nothing is asked or installed, and no `docs/conventions/ecosystems/` or legacy `.claude/ecosystems/` record is written; a key nothing resolved, or a tie, reads `skip (unresolved: <ecosystem>.<key>)`. It is non-interactive for the [confirmation gate](#code-fix-confirmation-gate). |

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
- **Run kind**: `--unattended`, else the ladder's "Run kind" detector

### 1. Detect ecosystems

First add each ecosystem the repo's instructions state or its files infer, per the ladder's "Covered ecosystems" in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md). Then, if an ecosystem filter was provided, use it; if `all`, run every covered ecosystem. Otherwise, classify changed files from `git status --porcelain` against each ecosystem's `globs` list; when the working tree is clean, fall back to the branch diff so checkpoint-committed work still gets classified. Resolve the default branch by **detection, not assumption**, never a hardcoded `main`/`master`, and assign it before use:

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

The loop probes candidate remotes in priority order, the remote the current branch tracks (`branch.<name>.remote`) first, then `origin` if present, then the rest, and selects the first one whose default branch resolves to a locally available tracking ref, never a hardcoded remote name. This handles an unpushed feature branch (no tracking remote) in a repo cloned with a different remote name (e.g. `git clone -o vendor`), and skips a remote that was added but never fetched (its default branch has no local `refs/remotes/<remote>/<branch>` to diff against) in favor of a later remote that does, the candidate is accepted only when `git rev-parse` confirms the tracking ref exists locally. Each candidate's default branch comes from that remote's own `HEAD` (not the current branch's upstream, which on a pushed feature branch points at the feature branch itself and would make `merge-base` equal `HEAD`, yielding an empty diff), falling back to a `git ls-remote --symref` query when the local `HEAD` symref is absent. `merge-base` is taken against the fully-qualified remote-tracking ref `refs/remotes/$REMOTE/$DEFAULT_BRANCH`, which resolves without a local branch of that name and, like the `rev-parse` verify, cannot be misparsed as an option when the remote name begins with a dash (`git clone --origin=-x`); the `git ls-remote` probe terminates option parsing with `--end-of-options` for the same reason. If no candidate yields a locally available default branch, skip the branch-diff path rather than guessing. A caller passing an explicit changed-file list (e.g. `/verification:confirm`) overrides both detection paths. Cross-cutting runs alongside detected ecosystems when any text file changed and the repository records or states a cross-cutting command.

Auto-detection algorithm:

1. With the stated and inferred ecosystems already added (above), resolve each covered ecosystem's config per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) (consumer `docs/conventions/ecosystems/<ecosystem>.yaml`, or the legacy `.claude/ecosystems/` file for a name absent there, when present, else what the repo's build files infer, named with its globs in the report, else ask; a key nothing resolves reads `skip (unresolved: <ecosystem>.<key>)`, and a malformed consumer file warns and degrades to inference, never a hard stop). An unattended run (the ladder's "Run kind") resolves commands by the ladder's "Unattended runs" instead: recorded, stated, then inferred, and a key none resolves reads `skip (unresolved: <ecosystem>.<key>)`. Skip any ecosystem whose resolved `enabled` is `false` (a consumer opt-out). Excluded even under `all`
2. For each ecosystem, match its `globs` against the changed-files list
3. Run every ecosystem with ≥1 glob match whose `opt-in` condition holds, plus cross-cutting when any text file changed and the repository records or states a cross-cutting command (with neither, cross-cutting adds no row and its files go to the `Outside every ecosystem:` line). This binary run/skip treatment applies cleanly when `opt-in` describes a single condition for the whole `check-cmd`: unmet → excluded from the run but still reported (see sections 2 and 3 below, `skip (opt-in unmet: ...)`; never silently omitted). When `opt-in` instead describes multiple independent per-tool conditions bundled into one opaque command string (one tool always, another only with its own config present), this rule does not apply. `check-cmd`/`fix-cmd`/`code-fix-cmd` is a single opaque string with no way to run one sub-tool's portion without the other, so run it whole and report its real output. The known atomicity limitation this leaves open is in `/toolchain:check`'s Gotchas.
4. A changed file is unclaimed when no resolved ecosystem's `globs` match it, cross-cutting's `**` aside: that glob is never a claim by itself, whether cross-cutting runs or is disabled. A match by any other ecosystem counts, even one that is disabled or skipped for an unmet opt-in: that row already reports the consumer's choice. Collect each unclaimed text file for the report's two fixed lines (section 3). Under `all` the changed files still come from the detection paths above; an ecosystem filter skips this step. A deleted file is not named. A binary file stays quiet. Decide binary with `git ls-files --eol -c -o -- <file>`: the file is binary when Git identifies its working-tree content as not text ([`--eol`](https://git-scm.com/docs/git-ls-files#Documentation/git-ls-files.txt---eol)). A path with no working-tree content is deleted or not a regular file, never binary. One command serves a working-tree change, the branch diff and a caller-supplied changed-file list.

If neither detection path yields changes and no filter specified: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:lint all` to check the full repo, or `/toolchain:lint <ecosystem>` for a specific filter." and stop. If files changed but no ecosystem runs, print the unclaimed-file line (when it names any file) instead of the table, and stop, unless the secret scan's opt-in holds (a `.gitleaks.toml` at the root): then run the [Secret scan](#secret-scan), record the Overall line (section 5), and report its row, the unclaimed-file lines and the Overall line.

### 2. Run linters per ecosystem

**Command selection by mode:**

The record's `lint-cmd` is the repository's report-only lint command; a check run takes it over
`check-cmd`. No hook runs a record's command, so this skill and `/toolchain:check` are where it runs.

| Mode | Command key | Gate |
|------|-------------|------|
| check (default) | `lint-cmd` when the record holds a non-null one, else `check-cmd` | none (read-only) |
| `--fix` | `fix-cmd` | none beyond the flag (format-only by contract) |
| `--code-fix` | `code-fix-cmd` | [confirmation gate](#code-fix-confirmation-gate) + [scope fence](#code-fix-scope-fence) |

Honor each ecosystem's `opt-in`: for a single-condition ecosystem, an unmet condition skips the whole ecosystem, reporting `skip (opt-in unmet: <condition, one short phrase>)` visibly (never a silent omission) in every column that ecosystem's row has. This skip counts toward the table's total ecosystem count but never toward the FAIL count, the same precedent as a missing-tool skip. For a multi-tool ecosystem whose `check-cmd` bundles multiple sub-tools into one opaque string, this binary treatment doesn't apply. Run and report `check-cmd`/`fix-cmd`/`code-fix-cmd` whole; see `/toolchain:check`'s Gotchas for the known atomicity limitation.

**`<files>` substitution:** expand to the ecosystem-scoped changed-file list (paths relative to the execution root). Prefer this scoped list over whole-tree `.` / `./...` whenever the command string contains `<files>`. Under `/toolchain:lint all` with an empty detection set, expand to the matching files under each project root (or the repo root) rather than inventing a silent whole-tree rewrite for code-fix, and still apply the [file-cap](#code-fix-scope-fence) to that expanded set.

**Go `*.go` filter for format/code-fix:** ecosystem `globs` include `go.mod` / `go.sum`, but `gofmt -w` and `golangci-lint run --fix` receive Go source only, and golangci-lint takes named files from one package per run ([golangci-lint quick start: Linting](https://golangci-lint.run/docs/welcome/quick-start/#linting)). When substituting `<files>` into Go `fix-cmd` / `code-fix-cmd`, drop every non-`.go` path first. For `golangci-lint run --fix`, further partition the remaining `.go` paths by parent directory and invoke once per directory (never pass a multi-directory file list in one process). If filtering leaves zero `.go` files, skip that Go format/code-fix command and report the skip rather than invoking the tool on module metadata alone.

Per-project walking (ecosystems with `project-discovery`):

- python: walk each `pyproject.toml` directory and run check/fix from there
- typescript: walk each `package.json` directory and run check/fix from there
- go: walk each `go.mod` directory and run check/fix from there (a root `./...` invocation stops at a nested module boundary)

Tool presence: verify on `PATH` before each ecosystem the tool its commands are invoked through (the runner or wrapper the command starts with, not the tools it runs behind it); report `skip (tool missing: <tool>)` with `install-hint` when missing, never `FAIL`. The probe is per ecosystem, not per sub-tool: a sub-tool bundled inside an opaque compound `check-cmd` is not probed, so its absence surfaces at execution time as a real non-zero exit and the ecosystem reports `FAIL`, not `skip`, unless the record declares it under `requires`. Same rule `/toolchain:check` states, so both skills classify an identical environment identically.

Declared prerequisites: after the tool-presence check and a met single-condition `opt-in` (an unmet one skips without probing), run the probes the resolved `requires` lists for the command this mode runs (`check-cmd`, `fix-cmd` or `code-fix-cmd`), by `/toolchain:check`'s "Declared prerequisites" rules. With any entry absent, the command does not run: every column it fills reads `skip (prerequisite missing: <name>)`, with the entry's `hint` below the table (and, for an entry with an `install` object, the provisioning step that installs it, as `/toolchain:check` names it), and the run goes on to the next ecosystem. A probe that errors, cannot start or passes 30 seconds reads the same skip, never `FAIL`. Never install a declared prerequisite and never run its `hint`. Under `--code-fix` no probe runs before the [confirmation gate](#code-fix-confirmation-gate) grants an apply: the plan lists each prerequisite `requires` declares for `code-fix-cmd` as `not probed yet`, so `--dry-run`, a non-interactive run without `--yes` and a declined confirmation run no probe at all. Once the gate grants the apply, the probes run, and an absent entry skips that ecosystem's `code-fix-cmd` with the same `skip (prerequisite missing: <name>)` report.

Tool pins (`tool-pin` sub-key, e.g. zizmor): when the resolved config pins a tool version, warn if the installed version drifts from the pin. A record sets a pin only for a tool whose version the repository owns itself (a manifest, lockfile, or version input its own workflow sets) and omits it when the version comes from a shared default, such as a composite action's input default, since a copy drifts. No pin, no check.

When a resolved command names `$EC_BIN`, resolve it for editorconfig-checker binary-name variants before substituting it into the command:

```bash
EC_BIN=""
if command -v ec >/dev/null 2>&1; then EC_BIN=ec
elif command -v editorconfig-checker >/dev/null 2>&1; then EC_BIN=editorconfig-checker
elif command -v ec-windows-amd64 >/dev/null 2>&1; then EC_BIN=ec-windows-amd64
fi
```

### Secret scan

In check mode, when a `.gitleaks.toml` sits at the repository root, run the secret scan from the repository root:

```bash
gitleaks detect --source . --redact --no-banner --no-git
```

The skill states the command, so the ladder does not resolve it, and an unattended run runs it like an attended one and logs it as `assumed: secret-scan.check-cmd=gitleaks detect --source . --redact --no-banner --no-git (SKILL.md, .gitleaks.toml)`. It runs on every check-mode run with changed files, `all` and an ecosystem filter included, whether or not any record exists or any ecosystem runs. It runs even when another command already ran `gitleaks`: a compound `check-cmd` exits with its last line's status, so its row can read `pass` over a secret finding.

Report it as its own `secret-scan` row with one Lint column: `pass` on exit 0, `FAIL` on a finding or any other non-zero exit, and `skip (tool missing: gitleaks)` with the hint `winget install Gitleaks.Gitleaks | brew install gitleaks` when `gitleaks` is not on `PATH`, an environment skip that leaves the run `INCOMPLETE`. With no `.gitleaks.toml` at the root it reads `skip (opt-in unmet: no .gitleaks.toml at the repo root)`. The row counts toward the table's totals like an ecosystem row, and it claims no file for the unclaimed-file lines. `--fix` and `--code-fix` do not run it.

### Code-fix confirmation gate

`--code-fix` mutates semantics, not just whitespace, the only `/toolchain:lint` path that does. Always emit the plan first:

```text
Code-fix plan — ecosystems: <list> (<N> files scoped)
- python: uv run ruff check <files> --fix --no-unsafe-fixes --unfixable F401  (<n> files)
- go: golangci-lint run --fix <files>  (<m> files)
- typescript: (no code-fix-cmd) — skip
- <ecosystem with requires>: <code-fix-cmd>  (<k> files; prerequisite <name>: not probed yet)
```

Then gate on session context and flags. Every side-effect path is explicitly gated, the gate never self-downgrades unattended:

| Session | Flags | Gate |
|---|---|---|
| Interactive | `--code-fix` only | Confirm with the user before applying. Honor scope narrowing ("only python"). |
| Interactive | `--code-fix --yes` | Skip the confirmation prompt and apply (still honor the file-cap unless `--all-files`). |
| Interactive or any | `--code-fix --dry-run` | Emit the plan and stop. Mutate nothing. |
| Non-interactive (`--unattended`, `CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop, or a run that cannot tell) | `--code-fix` without `--yes` | Stop after the plan. Mutate nothing. The plan is the report. Re-run with `--yes` to apply. |
| Non-interactive | `--code-fix --yes` | Apply (still honor the file-cap unless `--all-files`). |

`--code-fix` opts into code-changing fix mode; `--yes` is the separate, explicit consent to mutate a tree with no human watching. A non-interactive session with no `--yes` is never consent. Bare `--fix` does not enter this gate.

### Code-fix scope fence

Before applying `--code-fix`:

1. **Changed-files allowlist.** Scope each `code-fix-cmd` to the ecosystem's changed-file list via `<files>` (or the expanded `all` set). Do not silently retarget a whole-tree `.` / `./...` when a non-empty scoped list exists.
2. **File cap (default 40).** Sum the scoped files across ecosystems that will actually run a non-null `code-fix-cmd`. If the sum exceeds 40 and `--all-files` is absent, emit the plan, report `file-cap exceeded (<count> > 40; pass --all-files to override)`, and stop. Mutate nothing.
3. **No LOC auto-budget.** Do not invent a line-count ceiling; the confirmation plan (file list + commands) is the pre-apply review surface. After apply, surface `git diff --stat` so the operator can see blast radius.

### 3. Present results

In check mode, settle the Overall line and record it (section 5) before writing this report, so the report is the reply's last text.

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

Use `pass`, `FAIL`, a named skip, or `—` (not applicable). Every skip names its reason in `/toolchain:check`'s named classes, and its class decides whether it blocks a "done" claim exactly as `/toolchain:check`'s report table (its section 3) classifies it: `skip (tool missing: <tool>)`, `skip (prerequisite missing: <name>)` and `skip (unresolved: <ecosystem>.<key>)` are environment skips and block "done"; `skip (opt-in unmet: <condition>)` is the consumer's opt-in and does not. Lint installs nothing and runs no CI-parity gates, so it never emits the `dependencies missing` or `unsupported` classes.

An ecosystem's Status and the Overall line read `FAIL` when any cell failed, `INCOMPLETE` when nothing failed but an environment skip remains, and `PASS` only when neither holds. `INCOMPLETE` names each cause with its reason (e.g. `Overall: INCOMPLETE (3 of 4 ecosystems passed; markdown: skip (tool missing: markdownlint-cli2))`), so a caller such as `/verification:confirm` holds its verdict on a lint-only environment gap. An opt-in-unmet skip or a `—` cell never makes a run `INCOMPLETE`.

Split lint and format into separate columns where the ecosystem has both (dotnet, python, bash). Use a single "Lint" column for ecosystems with only one tool (markdown, yaml, powershell). An opt-in-unmet skip fills every column that ecosystem's row has.

If `--fix` was used, note which ecosystems were format-fixed vs which have no `fix-cmd`.

If `--code-fix` was used (and applied), note which ecosystems ran `code-fix-cmd` vs which have none, and show `git diff --stat` for blast radius.

Show failing output below the table. Truncated to key error lines, not the full dump. Any run prints, for each unresolved key, what it read; an unattended run also prints each `assumed:` line and any tied candidates (ladder "Unattended runs").

Below the table, name every unclaimed changed text file (section 1, step 4) on one of two fixed lines, printed word for word even when a note elsewhere in the reply says the same thing:

- `No ecosystem linter (cross-cutting text checks only): <path>, <path>` only when cross-cutting's check command executed in this invocation (its row reads `pass` or `FAIL`), so its checks covered them;
- `Outside every ecosystem: <path>, <path>` in every other case, including a cross-cutting row that is a skip.

Neither line changes a Status or the Overall line, and no binary file is on either. Say nothing about a binary file outside every ecosystem: no table row, no bullet, and no note that it is binary, was skipped or was ignored. Tool output the report shows, such as failing lines or `git diff --stat`, stays as printed.

### 4. Fix mode notes

- **`--fix`:** auto-fix capability derives from a non-null `fix-cmd`. Report check-only ecosystems alongside format fixes: "Fixed formatting in dotnet, python, bash. markdownlint had no remaining auto-fixes."
- **`--code-fix`:** capability derives from a non-null `code-fix-cmd`. Ecosystems with only `fix-cmd` (format-only) are not code-fixed under this flag. Tell the operator to use `--fix` for those. Example: "Applied code-fix in python, go. typescript has no code-fix-cmd. Use `--fix` for format-only ecosystems (dotnet, bash, …)."

**Consumer overrides:** a consumer who still puts code-changing autofixes in `fix-cmd` keeps that behavior under `--fix` (their file wins). Prefer migrating those verbs into `code-fix-cmd` so bare `--fix` stays format-only.

### 5. Record the result

In check mode, before writing the report, record the settled Overall line for the tree it ran on, in its own Bash call, with the line exactly as the report will print it inside single quotes (write a `'` in it as `'\''`):

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/record-result.mjs" --skill lint --dir "$REPO_ROOT" --overall '<the Overall line>'
```

The plugin's Stop hook reads it at turn end the same way it reads `/toolchain:check`'s record. Record nothing for `--fix` or `--code-fix`: the fix changes the tree, so the check that would count is the next check-mode run. Skip it too when an ecosystem filter narrowed the run (`all` and a caller's changed-file list do not narrow it), and when the run stopped at "No changes found" or with no ecosystem to run and no secret scan run. A run with no ecosystem to run that did run the secret scan (section 1's opt-in case) records its Overall line like any other check-mode run, so a `secret-scan` FAIL reaches the Stop hook. A failed record (exit 2, for example where a sandbox blocks the git calls that hash the tree, or exit 1 for a line it rejects) changes nothing in the report: put one `Not recorded: <the script's reason>` line above the table, and still end the reply with the full report, its table, the lines below it and the Overall line.

## Edge cases

- **No git changes but `/toolchain:lint all`**: run all applicable ecosystems (useful after rebase or pull)
- **Missing tools**: report as `skip (tool missing: <tool>)` with the install hint, not as failure, and never as done: the Overall line reads `INCOMPLETE`. Scoped to the tool the ecosystem's commands are invoked through, not every sub-tool a compound command reaches (an un-probed sub-tool's absence is a real non-zero exit, so `FAIL`, unless the record declares it under `requires`; see `/toolchain:check`'s Gotchas)
- **Declared prerequisite absent**: report as `skip (prerequisite missing: <name>)` with its hint, never `FAIL` from a crashed command or a `PASS` from the wrong build of a tool; the Overall line reads `INCOMPLETE`
- **Opt-in unmet**: report as `skip (opt-in unmet: ...)` with the condition, not as failure and not a silent omission (e.g., a record whose `opt-in` names a config file the repository lacks)
- **Multiple projects in same ecosystem**: run per-project (each `pyproject.toml`, each `package.json`)
- **File outside any ecosystem**: a text file is named on one of the two unclaimed-file lines; a binary file (images, archives) outside every ecosystem gets no mention in the reply, not even to say it was skipped
- **CWD drift**: always use absolute paths from `$REPO_ROOT`
- **`--code-fix` over file-cap without `--all-files`**: plan + stop, never mutate
- **`--code-fix` in non-interactive session without `--yes`**: plan + stop, never mutate
- **Both `--fix` and `--code-fix`**: prefer `--code-fix`, note `--fix` ignored

## Next

- Lint clean, build and tests not yet run: /toolchain:check.
- Lint clean as part of finishing a change: /verification:confirm.

## Relationship to other skills

- **Composes from `/toolchain:check`**: `/toolchain:check` owns the shared run rules and gotchas. Reference it rather than duplicating
- **Composed by `/verification:confirm`** (the separate `verification` plugin, when enabled): the lint leg of full verification
- **After a simplify/cleanup pass**: run `/toolchain:lint` to catch formatting issues the cleanup introduced
- **Before commit**: `/toolchain:lint --fix` is a quick pre-commit **format** cleanup without the overhead of a full build. Use `/toolchain:lint --code-fix` (interactive confirm, or `--yes` when headless) only when you intentionally want semantic lint autofixes.
