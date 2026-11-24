---
description: "Build, test, and lint verification for changed files in each ecosystem the repository records or its build files imply, running only the project's own commands and reporting any it cannot resolve. Use when: 'does it compile', 'run tests', 'build it', 'run the tests', 'does this still build', 'check it', or after any code edit. Lint only: /toolchain:lint; outcome verification: /verification:confirm."
user-invocable: true
disable-model-invocation: false
argument-hint: "[ecosystem] [--unattended]"
metadata:
  workflow-stage: verify
  summary: Build, test, and lint changed files across detected ecosystems
---

**Arguments.** `[ecosystem] [--unattended]`. e.g., /toolchain:check dotnet, /toolchain:check python, /toolchain:check all, /toolchain:check --unattended. Default: auto-detect from git status

## Repository context. Gather first

<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->
Run each command below as its own Bash call, all sent together in one message ([worktree isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)).
Keep any bound in the command's own pipe ([output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
<!-- END GENERATED: gather-block -->

- Working tree status (empty = clean), `git status --porcelain | head -20`
- Current branch, `git branch --show-current`

## Purpose

Detects the ecosystems the changed files touch and runs each one's build → test → lint. Run it as `/toolchain:check` or `/toolchain:check <ecosystem>`. `/toolchain:lint`, `/verification:confirm` (when enabled) and verification agents compose it for detection and command resolution instead of keeping their own tables.

Commands are resolved, not hardcoded: the three-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) reads the consuming repo's tracked `docs/conventions/ecosystems/<ecosystem>.yaml` (or the legacy `.claude/ecosystems/` file for a name absent there) first, then infers from its build files, then asks. The plugin ships no default command: a key nothing resolves is reported unresolved and runs nothing.

## Arguments

`$ARGUMENTS` is an optional ecosystem filter: any covered ecosystem id, meaning one recorded, stated or inferred this run ([resolution ladder](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) "Covered ecosystems"), except the lint-only `yaml` and `cross-cutting`. A consumer record such as `docs/conventions/ecosystems/rust.yaml` makes `rust` a filter. Aliases: `ts`/`node` → `typescript`, `shell` → `bash`, `ps`/`pwsh` → `powershell`, `md` → `markdown`, `golang` → `go`. Literal `all` runs every covered ecosystem. The lint-only `yaml` and `cross-cutting` surfaces belong to `/toolchain:lint`; this skill never runs them (and never matches `cross-cutting`'s `**` glob).

`--unattended` marks the run unattended; strip it before reading the ecosystem filter. A run without it is still unattended when the ladder's "Run kind" says so, including a run that cannot tell whether a person is present. An unattended run resolves commands by the ladder's "Unattended runs": it runs only a recorded, stated or inferred command, logs each as `assumed:` with its source, asks nothing, installs nothing, writes no `docs/conventions/ecosystems/` or legacy `.claude/ecosystems/` record, and reports a key nothing resolved, or a tie, as `skip (unresolved: <ecosystem>.<key>)`.

Read on demand:

- [context/gates.md](context/gates.md). CI-parity gates
- [context/sarif.md](context/sarif.md). Roslyn SARIF output, jq parser patterns, AI consumption

## Workflow

### 0. Resolve repo root

Run `git rev-parse --show-toplevel` as its own Bash call, and write its output in place of `$REPO_ROOT` in every later command. What persists between Bash calls: [Tools reference § What persists between commands](https://code.claude.com/docs/en/tools-reference#what-persists-between-commands).

All commands use absolute paths. Never `cd` and lose context.

### 1. Detect ecosystems

First add each ecosystem the repo's instructions state or its files infer, per the ladder's "Covered ecosystems". With an ecosystem argument, use it; with `all`, run every covered ecosystem. Otherwise match the changed files from `git status --porcelain` against each covered ecosystem's resolved `globs`. When another skill calls this one with a changed-file list, use that list instead. Skip any ecosystem whose resolved `enabled` is `false`, even under `all`.

If the working tree is clean, fall back to the branch diff, so work already committed at green checkpoints still gets classified. Detect the default branch, never hardcode `main` or `master`, with this script as written:

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

If neither path yields changes and no `$ARGUMENTS`: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:check all` to verify the full repo, or `/toolchain:check <ecosystem>` for a specific ecosystem." and exit.

**Files outside every ecosystem.** A changed file is outside every ecosystem when no resolved ecosystem's `globs` match it, cross-cutting's `**` aside: that glob is never a claim by itself, and this skill never runs cross-cutting. A match by any other ecosystem counts, even the lint-only `yaml` surface or one that is disabled or skipped for an unmet opt-in. Collect each such text file for the report's `Outside every ecosystem` line; a deleted file is not named. Under `all` the changed files still come from the detection paths above; an ecosystem argument skips this step. A binary file stays quiet. Decide binary with `git ls-files --eol -c -o -- <file>`: the file is binary when Git identifies its working-tree content as not text ([`--eol`](https://git-scm.com/docs/git-ls-files#Documentation/git-ls-files.txt---eol)). A path with no working-tree content is deleted or not a regular file, never binary. One command serves a working-tree change, the branch diff and a caller-supplied changed-file list. If files changed but no ecosystem runs, print the `Outside every ecosystem` line (when it names any file) instead of the table, and exit.

**Conversation-aware targeting.** When the conversation has been working in specific files or projects, scope the build to what was touched. The ecosystem's `anchor` is the default entry point; substitute a narrower project file when changes stay in one project. For .NET, use the specific `.csproj` for a one-project change, and the solution file when changes span projects or touch shared files (`.props`, `.targets`, the solution file).

### 1.5 Resolve each ecosystem's command surface

Resolve `globs`, `build-cmd`, `test-cmd`, `test-changed-cmd`, `check-cmd`, `lint-cmd`, `fix-cmd`, `code-fix-cmd`, `anchor`, `project-discovery`, `install-hint`, `requires`, `gates` and `notes` per the ladder:

1. Consumer `docs/conventions/ecosystems/<ecosystem>.yaml` (+ `.local.yaml` personal override, `~/.claude/ecosystems/` user-global, additive per key; the legacy `.claude/ecosystems/` file for a name absent there) → authoritative.
2. Absent → infer from the repo's build files, name the inferred id and its globs in the report, and offer to persist via `/toolchain:setup`.
3. Cannot infer → ask; offer to persist.

A key no rung resolves runs nothing and reads `skip (unresolved: <ecosystem>.<key>)`. A malformed consumer file warns and degrades to rung 2, never a hard stop.

That ladder is the attended one. An unattended run (the ladder's "Run kind") takes the ladder's "Unattended runs" in its place: recorded, then stated, then inferred, and no rung 3. A key none of them resolves runs nothing and reads `skip (unresolved: <ecosystem>.<key>)`.

### 2. Run checks

For each affected ecosystem run the resolved `build-cmd`, `test-cmd` and `check-cmd`, in that order; skip a null command. Where the record holds a non-null `lint-cmd`, run it in place of `check-cmd`: it is the repository's report-only lint command, and no hook runs it. Where the record holds a non-null `test-changed-cmd` and the run has changed files for the ecosystem, run it in place of `test-cmd`: it is the change-scoped test command the repository's CI also calls. Under `all`, or with no changed files for the ecosystem, run `test-cmd`. When the record holds one, name the key that ran below the table (`Test: test-changed-cmd` or `Test: test-cmd`). Substitute `<solution-or-project-file>` (per `anchor`), `<project-dir>` (each root `project-discovery` finds) and `<files>` (that ecosystem's changed files). Stop an ecosystem at its first failure and continue with the next. A skipped command is not a failure: the ecosystem's next command still runs.

**What counts as a check.** A cell reads `pass` only when its command started, exercised the project, and exited 0. Two outcomes look green and are not:

- **Syntax only.** A command that only parses the files (`bash -n`, `python -m py_compile`, `node --check`) checks no behavior. It fills no Build or Test cell: report that cell `syntax only`.
- **Failed to start.** Exit 126 or 127, a spawn or permission error, or a runner that aborted before running anything (an import error while collecting tests) produced no result. When the cause is missing declared dependencies, apply the install rule below; otherwise the cell is `FAIL` with the output shown.

**Passed on retry.** A test that failed and then passed on a rerun the project configures is a flaky result, not a clean pass. When the test output reports any, the Test cell reads `pass (flaky: N)`, the ecosystem Status `PASS (flaky: N)`, the Overall line adds the summed count (e.g. `Overall: PASS (2 of 2 ecosystems passed; flaky: 1)`), and each flaky test is named below the table. It does not make the run `FAIL`. Count only what the runner's own output marks as a retried pass, such as a rerun or flaky count in its summary line. When the project's test config sets retries but the output does not separate a retried pass from a clean one, the Test cell reads `pass` with the line `retries configured, flaky count not reported` below the table, never a plain clean pass. A runner with no retry of its own earns a flaky count only from a retry wrapper the project documents.

**Run signals to echo** below the table, from the same test output, when present:

- **Shuffle seed.** Any order or random seed the runner printed. When the project shuffles but the output hides the seed (a quiet flag can hide the header that prints it), say so and name the runner's replay form, from the project's docs or the runner's own documentation.
- **Slowest tests.** The runner's slowest-tests section, top entries only. When the output has none, one line names the runner's own flag or config setting that turns it on, for the project's own `test-cmd` or test config. Never edit the resolved `test-cmd` to add it: command strings are opaque.

**Missing declared dependencies.** When the ecosystem's tool is on `PATH` but a command cannot start because the project's declared dependencies are not installed (a package or module not found, a project not restored), install them once and rerun that command, within these limits:

- Install only in an attended run. An unattended run (the ladder's "Run kind": an `--unattended` argument, `CLAUDE_CODE_REMOTE` set, `claude -p`, an autonomous loop, or a run that cannot tell) installs nothing: report `skip (dependencies missing: unattended run)`.
- Never install a declared prerequisite (below), attended or not: its probe decides the cell before the command runs.
- Install only from the committed lockfile, with install scripts disabled, and only with one of these commands: `npm ci --ignore-scripts`, `uv sync --frozen --no-build --no-install-local`, `dotnet restore --locked-mode`. Any other package manager installs nothing: report `skip (dependencies missing: no vetted install)`. With no lockfile, do not install; report `skip (dependencies missing: no lockfile)`. The uv command builds nothing at install time, so a third-party dependency that ships no wheel fails the install: report `skip (dependencies missing: no wheel for <package>)`. Pointer: for the flags, see <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-build> and <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-install-local>.
- Stay within the session's permission mode. Never use `sudo` or any other elevation, and never retry a denied install another way: report `skip (dependencies missing: install denied)`.
- Never install a tool. A runner missing from `PATH` stays `skip (tool missing: <tool>)`.
- Capture `git status --porcelain` and a hash of `git diff HEAD --binary` before the install and again after it, so a file that was already modified and changes again is caught. If either differs, stop the whole run and report `Overall: STOPPED (dependency install changed: <paths>)`. Run no further check: the tree is no longer the one under test.

**Tool presence.** Before each ecosystem runs, check that the tool its commands are invoked through is on `PATH` (the runner or wrapper the command starts with, not the tools it runs behind it). Missing: report `skip (tool missing: <tool>)` with the ecosystem's `install-hint`, never `FAIL`. Do not probe the sub-tools inside a compound `check-cmd`: one that is absent fails at run time, and that real non-zero exit is reported as `FAIL`, unless the record declares it under `requires`.

**Declared prerequisites.** The resolved `requires` lists, per command key, what that command needs beyond its tool on `PATH`: a runtime package, or a tool at the build the repo pins for CI. After the tool-presence check passes, and after a single-condition `opt-in` is met (an unmet one skips `check-cmd` without probing), run each of the command's entries' `probe` before the command: one Bash call per probe with the Bash tool's `timeout` set to 30000, from `$REPO_ROOT`, or from each location the command runs from when the entry sets `run-from: ecosystem`, with `$REPO_ROOT` substituted. Exit 0 means present. Any other exit, a probe that cannot start, and one that times out mean absent, never `FAIL`.

- With any entry absent, do not run the command. Its cell reads `skip (prerequisite missing: <name>)`, naming each absent entry (`<name>, <name>`), with each entry's `hint` below the table. For an entry that carries an `install` object, the line below the table also names the provisioning step that installs it, `provision-prerequisites.sh` in the source-control plugin (the worktree helper runs it at creation), and its lockfile; the check itself never runs that step.
- Under `run-from: ecosystem` the command still runs at the locations where every probe passed. The cell reads `FAIL` when any of those runs failed, else the skip, with the skipped locations listed below the table, and `pass` only when it ran and passed everywhere.
- One absent entry skips the whole command, every tool bundled in its string included.
- Never install a declared prerequisite and never run its `hint`, in any run. Compare no version yourself: the probe is the whole test, and `tool-pin` stays a drift warning.
- A `gates[]` item's own `requires` applies the same way to that gate's `cmd` ([context/gates.md](context/gates.md)).

**Opt-in gate (lint phase only).** Before `check-cmd`, evaluate the resolved `opt-in` condition, if any; build and test always run. When `opt-in` is one condition for the whole `check-cmd` (such as one linter's config file being present), unmet means the Lint cell reads `skip (opt-in unmet: <condition, one short phrase>)` and `check-cmd` does not run; never omit it silently. When `opt-in` lists several per-tool conditions bundled in one command string (one tool always, another only with its own config present), run `check-cmd` whole and report its real output: a command string cannot be partly skipped. An opt-in skip counts toward the ecosystem total, never toward the FAIL count, and never blocks a "done" claim.

**CI-parity gates.** When an affected ecosystem resolves a non-empty `gates` array, or the project documents CI-parity checks in its `CLAUDE.md`, `.claude/rules/` or a commands reference, read [context/gates.md](context/gates.md) and run them by its rules after build → test → lint. A gate runs even when an earlier phase failed, and a fired gate that fails makes the run `FAIL`.

### 3. Report results

Settle the Overall line and record it (section 4) before writing this report, so the report is the reply's last text.

```text
## Build Results

| Ecosystem  | Build | Test | Lint | Status |
|------------|-------|------|------|--------|
| dotnet     | pass  | pass | pass | PASS   |
| python     | —     | pass | FAIL | FAIL   |

Gates: go-mod-tidy-drift — FAIL (run go mod tidy and commit the updated go.mod/go.sum)

Overall: FAIL (1 of 2 ecosystems failed, 1 gate failed)
```

Use `pass`, `FAIL`, `syntax only`, a named skip, or `—` (not applicable: the command is null in the ecosystem config). Show failing command output below the table. Below the table, any run prints, for each unresolved key, what it read, and an unattended run also prints each `assumed:` line and any tied candidates (ladder "Unattended runs"); the Overall line names each unresolved cell as a cause, e.g. `Overall: INCOMPLETE (0 of 2 ecosystems passed; markdown: skip (unresolved: markdown.build-cmd, markdown.test-cmd, markdown.check-cmd))`. Every skip names its reason, and its class decides whether it blocks a "done" claim:

| Cell | Class | Blocks "done" |
|------|-------|---------------|
| `skip (tool missing: <tool>)` | environment | yes |
| `skip (dependencies missing: <reason>)` | environment | yes |
| `skip (prerequisite missing: <name>)` | environment: a `requires` probe found it absent | yes |
| `skip (unsupported: <tool and capability>)` (gates only) | environment: the installed tool is below the gate's documented floor | yes |
| `skip (unresolved: <ecosystem>.<key>)` | environment: no source the run may use resolved a command for the key | yes |
| `skip (opt-in unmet: <condition>)` | consumer opt-in | no |
| `—` | not applicable | no |
| `syntax only` | not a check: when no other cell of the ecosystem passed, no real check ran | no, but never read as verified |
| `pass (flaky: N)` | retry-earned pass: N tests failed first and passed on a configured rerun | no, but never read as a clean pass |

An ecosystem's Status and the Overall line read `FAIL` when any cell or fired gate failed, `INCOMPLETE` when nothing failed but an environment skip remains or an ecosystem's only filled cells are `syntax only`, and `PASS` only when none of these holds. `INCOMPLETE` names each cause with its reason (e.g. `Overall: INCOMPLETE (1 of 2 ecosystems passed; python: skip (tool missing: uv))`, or `bash: no real check ran (syntax only)`), so a caller can say exactly what stayed unverified and whether it was an environment skip. A run the install rule stopped reads `STOPPED`. A `PASS` with any `pass (flaky: N)` cell carries the summed count, as in `Overall: PASS (2 of 2 ecosystems passed; flaky: 1)`.

Below the table, name every changed text file outside every ecosystem on one line, printed word for word even when a note elsewhere in the reply says the same thing: `Outside every ecosystem: <path>, <path>`. Since this skill never runs cross-cutting, `/toolchain:lint`'s cross-cutting-only line never appears here. The line changes no Status and no Overall line, and no binary file is on it. Say nothing about a binary file outside every ecosystem: no table row, no bullet, and no note that it is binary, was skipped or was ignored. Tool output the report shows, such as failing lines or `git diff --stat`, stays as printed.

When any gate fired, list each by name and outcome below the ecosystem table, with its remediation on failure. The Overall line then names both counts, pass or fail (e.g. `Overall: FAIL (0 of 2 ecosystems failed, 1 gate failed)`, `Overall: PASS (2 of 2 ecosystems passed, 1 gate passed)`), so it is clear whether a gate ran.

### 4. Record the result

Before writing the report, record the settled Overall line for the tree it ran on, in its own Bash call, with the line exactly as the report will print it inside single quotes (write a `'` in it as `'\''`):

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/record-result.mjs" --skill check --dir "$REPO_ROOT" --overall '<the Overall line>'
```

The plugin's Stop hook reads it when the turn ends and warns when the line is not `PASS`, or when no result is recorded for the current tree. An edit after the run changes the tree, so the record no longer counts. A failed record (exit 2, for example where a sandbox blocks the git calls that hash the tree, or exit 1 for a line it rejects) changes nothing in the report: put one `Not recorded: <the script's reason>` line above the table, and still end the reply with the full report, its table, the lines below it and the Overall line. Skip this step when an ecosystem argument narrowed the run (a narrowed `PASS` does not cover the whole tree; `all` and a caller's changed-file list do), and when the run stopped at "No changes found" or with no ecosystem to run.

## For other skills referencing /toolchain:check

- **Command tables**: resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md), including when embedding commands in an agent prompt.
- **Full verification**: invoke `/toolchain:check` or `/toolchain:check <ecosystem>` via the Skill tool.
- **Lint only**: invoke `/toolchain:lint` or `/toolchain:lint <ecosystem>` via the Skill tool; it resolves through the same ladder and also owns the `yaml` and `cross-cutting` surfaces.

## Next

- Overall `PASS`: /verification:confirm before committing.
- Overall `FAIL`: /testing:diagnose.

## Related

- Lint and format checks only without build or tests: /toolchain:lint.
- Persist ecosystem commands: /toolchain:setup.

## Gotchas (cross-ecosystem)

- **CWD drift**, the most common source of false failures. Always use absolute paths.
- **A green exit that checked nothing.** A syntax-only command, or one that failed to start, is not a `pass`.
- **A green exit a retry earned.** Report `pass (flaky: N)`, never a plain `pass`.
- **Missing tool is never done.** `skip (tool missing: <tool>)` makes the Overall line `INCOMPLETE`, not `FAIL` and not `PASS`. So do `skip (prerequisite missing: <name>)` and `skip (unresolved: <ecosystem>.<key>)`.
- **Nothing falls back.** With no record, inference or answer for a key (attended), or no record, statement or single inference (unattended), the run reports it unresolved; no default command runs instead.
- **Multi-tool `check-cmd` atomicity.** When a `check-cmd` chains a gated sub-tool after an unconditional one (`<linter> <files> && <formatter> -d <files>`), the opt-in gate cannot suppress just the gated part: both run whenever the unconditional one applies. The same opacity reaches the missing-tool rule: a sub-tool the ecosystem's probe never covers (one run through the runner the probe checks) is absent only at run time, so the Lint cell reports `FAIL`, not `skip`, unless the record declares it under `requires`. Report what the runner did, never a skip it did not perform. To avoid the `FAIL`, install the sub-tool, declare it under `requires`, or drop it from the record's `check-cmd`.
- **Multiple projects in one ecosystem.** Ecosystems with an `anchor` scope to it; ecosystems with `project-discovery` patterns walk each discovered project root.
