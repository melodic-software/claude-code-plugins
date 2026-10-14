---
description: "Build, test, and lint verification for changed files across detected ecosystems (.NET, Python, TypeScript, Go, Bash, PowerShell, Markdown), with the project's own commands overriding bundled defaults. Use when: 'does it compile', 'run tests', 'build it', 'run the tests', 'does this still build', 'check it', or after any code edit. Lint only: /toolchain:lint; outcome verification: /verification:confirm."
user-invocable: true
disable-model-invocation: false
argument-hint: "[ecosystem]"
metadata:
  workflow-stage: verify
  summary: Build, test, and lint changed files across detected ecosystems
---

**Arguments.** `[ecosystem]`. e.g., /toolchain:check dotnet, /toolchain:check python, /toolchain:check all. Default: auto-detect from git status

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into one invocation, so a worktree-isolated session screens each git read on its own:

- Working tree status (empty = clean), `git status --porcelain | head -20`
- Current branch, `git branch --show-current`

Keep the bound in the pipe; a read-time cap bounds nothing. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Pointers: what a large output returns, [Output limits](https://code.claude.com/docs/en/tools-reference#output-limits); how injected commands are grouped, [How injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run); why a pre-compute block carrying git is refused, `/source-control:worktree`'s gather-block reference, "The pre-compute block runs as one shell invocation". As of: 2026-10-11. Recheck trigger: either docs section changes, or that skill drops or renames that section.

## Purpose

Detects the ecosystems the changed files touch and runs each one's build → test → lint. Run it as `/toolchain:check` or `/toolchain:check <ecosystem>`. `/toolchain:lint`, `/verification:confirm` (when installed) and verification agents compose it for detection and command resolution instead of keeping their own tables.

Commands are resolved, not hardcoded: the four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) reads the consuming repo's tracked `.claude/ecosystems/<ecosystem>.yaml` first; the bundled defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the last-rung fallback. The consumer's file always wins.

## Arguments

`$ARGUMENTS` is an optional ecosystem filter: `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`. Aliases: `ts`/`node` → `typescript`, `shell` → `bash`, `ps`/`pwsh` → `powershell`, `md` → `markdown`, `golang` → `go`. Literal `all` runs every covered ecosystem. The lint-only `yaml` and `cross-cutting` surfaces belong to `/toolchain:lint`; this skill never runs them (and never matches `cross-cutting`'s `**` glob).

Per-ecosystem gotchas and primary-source detail, read for each ecosystem that runs:

- [context/dotnet.md](context/dotnet.md). .NET build, test, format
- [context/sarif.md](context/sarif.md). Roslyn SARIF output, jq parser patterns, AI consumption
- [context/python.md](context/python.md). Python lint, format, test
- [context/typescript.md](context/typescript.md). TypeScript compile, test, lint
- [context/bash.md](context/bash.md). ShellCheck, shfmt
- [context/powershell.md](context/powershell.md). PSScriptAnalyzer
- [context/go.md](context/go.md). Go build, test, lint, module discovery

## Workflow

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

All commands use absolute paths. Never `cd` and lose context.

### 1. Detect ecosystems

With an ecosystem argument, use it; with `all`, run every covered ecosystem. Otherwise match the changed files from `git status --porcelain` against each covered ecosystem's resolved `globs`. When another skill calls this one with a changed-file list, use that list instead. Skip any ecosystem whose resolved `enabled` is `false`, even under `all`.

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

**Conversation-aware targeting.** When the conversation has been working in specific files or projects, scope the build to what was touched. The ecosystem's `anchor` is the default entry point; substitute a narrower project file when changes stay in one project. For .NET, use the specific `.csproj` for a one-project change, and the solution file when changes span projects or touch shared files (`.props`, `.targets`, the solution file).

### 1.5 Resolve each ecosystem's command surface

Resolve `globs`, `build-cmd`, `test-cmd`, `check-cmd`, `fix-cmd`, `code-fix-cmd`, `anchor`, `project-discovery`, `install-hint`, `gates` and `notes` per the ladder:

1. Consumer `.claude/ecosystems/<ecosystem>.yaml` (+ `.local.yaml` overlay, `~/.claude/ecosystems/` user-global, additive per key) → authoritative.
2. Absent → infer from the repo's build files and offer to persist via `/toolchain:setup`.
3. Cannot infer → ask; offer to persist.
4. Otherwise → the bundled default at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/<ecosystem>.yaml`.

A malformed consumer file warns and degrades to rung 2, never a hard stop.

### 2. Run checks

For each affected ecosystem run the resolved `build-cmd`, `test-cmd` and `check-cmd`, in that order; skip a null command. Substitute `<solution-or-project-file>` (per `anchor`), `<project-dir>` (each root `project-discovery` finds) and `<files>` (that ecosystem's changed files). Stop an ecosystem at its first failure and continue with the next.

**What counts as a check.** A cell reads `pass` only when its command started, exercised the project, and exited 0. Two outcomes look green and are not:

- **Syntax only.** A command that only parses the files (`bash -n`, `python -m py_compile`, `node --check`) checks no behavior. It fills no Build or Test cell: report that cell `syntax only`.
- **Failed to start.** Exit 126 or 127, a spawn or permission error, or a runner that aborted before running anything (an import error while collecting tests) produced no result. When the cause is missing declared dependencies, apply the install rule below; otherwise the cell is `FAIL` with the output shown.

**Passed on retry.** A test that failed and then passed on a rerun the project configures is a flaky result, not a clean pass. When the test output reports any, the Test cell reads `pass (flaky: N)`, the ecosystem Status `PASS (flaky: N)`, the Overall line adds the summed count (e.g. `Overall: PASS (2 of 2 ecosystems passed; flaky: 1)`), and each flaky test is named below the table. It does not make the run `FAIL`. `context/<ecosystem>.md` records which output marks a retry-earned pass, and what to report when retries are configured but none is marked.

**Run signals to echo** below the table, from the same test output, when present:

- **Shuffle seed.** Any order or random seed the runner printed. When the project shuffles but the output hides the seed, say so and name the replay form from `context/<ecosystem>.md`.
- **Slowest tests.** The runner's slowest-tests section, top entries only. When the output has none, one line names how the project turns it on (from `context/<ecosystem>.md`). Never edit the resolved `test-cmd` to add it: command strings are opaque.

**Missing declared dependencies.** When the ecosystem's tool is on `PATH` but a command cannot start because the project's declared dependencies are not installed (a package or module not found, a project not restored), install them once and rerun that command, within these limits:

- Install only from the committed lockfile, with install scripts disabled, and only with one of these commands: `npm ci --ignore-scripts`, `uv sync --frozen --no-build --no-install-local`, `dotnet restore --locked-mode`. Any other package manager installs nothing: report `skip (dependencies missing: no vetted install)`. With no lockfile, do not install; report `skip (dependencies missing: no lockfile)`. The uv command builds nothing at install time, so a third-party dependency that ships no wheel fails the install: report `skip (dependencies missing: no wheel for <package>)`. Pointer: for the flags, see <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-build> and <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-install-local>. As of: 2026-10-02. Recheck trigger: either entry changes what it builds or installs.
- Stay within the session's permission mode. Never use `sudo` or any other elevation, and never retry a denied install another way: report `skip (dependencies missing: install denied)`.
- Never install a tool. A runner missing from `PATH` stays `skip (tool missing: <tool>)`.
- Capture `git status --porcelain` and a hash of `git diff HEAD --binary` before the install and again after it, so a file that was already modified and changes again is caught. If either differs, stop the whole run and report `Overall: STOPPED (dependency install changed: <paths>)`. Run no further check: the tree is no longer the one under test.

**Tool presence.** Before each ecosystem runs, check that the tool its commands are invoked through is on `PATH` (python's `uv`, not the `ruff` and `pyright` behind it). Missing: report `skip (tool missing: <tool>)` with the ecosystem's `install-hint`, never `FAIL`. Do not probe the sub-tools inside a compound `check-cmd`: one that is absent fails at run time, and that real non-zero exit is reported as `FAIL`.

**Opt-in gate (lint phase only).** Before `check-cmd`, evaluate the resolved `opt-in` condition, if any; build and test always run. When `opt-in` is ONE condition for the whole `check-cmd` (e.g. dotnet, python, go; any ecosystem whose resolved `opt-in` has this shape), unmet means the Lint cell reads `skip (opt-in unmet: <condition, one short phrase>)` and `check-cmd` does not run; never omit it silently. When `opt-in` lists several per-tool conditions bundled in one command string (bash: shellcheck always, shfmt only with an `.editorconfig` shell style), run `check-cmd` whole and report its real output: a command string cannot be partly skipped. An opt-in skip counts toward the ecosystem total, never toward the FAIL count, and never blocks a "done" claim.

**CI-parity gates.** When an affected ecosystem resolves a non-empty `gates` array, or the project documents CI-parity checks in its `CLAUDE.md`, `.claude/rules/` or a commands reference, read [context/gates.md](context/gates.md) and run them by its rules after build → test → lint. A gate runs even when an earlier phase failed, and a fired gate that fails makes the run `FAIL`.

### 3. Report results

```text
## Build Results

| Ecosystem  | Build | Test | Lint | Status |
|------------|-------|------|------|--------|
| dotnet     | pass  | pass | pass | PASS   |
| python     | —     | pass | FAIL | FAIL   |

Gates: go-mod-tidy-drift — FAIL (run go mod tidy and commit the updated go.mod/go.sum)

Overall: FAIL (1 of 2 ecosystems failed, 1 gate failed)
```

Use `pass`, `FAIL`, `syntax only`, a named skip, or `—` (not applicable: the command is null in the ecosystem config). Show failing command output below the table. Every skip names its reason, and its class decides whether it blocks a "done" claim:

| Cell | Class | Blocks "done" |
|------|-------|---------------|
| `skip (tool missing: <tool>)` | environment | yes |
| `skip (dependencies missing: <reason>)` | environment | yes |
| `skip (unsupported: <tool and capability>)` (gates only) | environment: the installed tool is below the gate's documented floor | yes |
| `skip (opt-in unmet: <condition>)` | consumer opt-in | no |
| `—` | not applicable | no |
| `syntax only` | not a check: when no other cell of the ecosystem passed, no real check ran | no, but never read as verified |
| `pass (flaky: N)` | retry-earned pass: N tests failed first and passed on a configured rerun | no, but never read as a clean pass |

An ecosystem's Status and the Overall line read `FAIL` when any cell or fired gate failed, `INCOMPLETE` when nothing failed but an environment skip remains or an ecosystem's only filled cells are `syntax only`, and `PASS` only when none of these holds. `INCOMPLETE` names each cause with its reason (e.g. `Overall: INCOMPLETE (1 of 2 ecosystems passed; python: skip (tool missing: uv))`, or `bash: no real check ran (syntax only)`), so a caller can say exactly what stayed unverified and whether it was an environment skip. A run the install rule stopped reads `STOPPED`. A `PASS` with any `pass (flaky: N)` cell carries the summed count, as in `Overall: PASS (2 of 2 ecosystems passed; flaky: 1)`.

When any gate fired, list each by name and outcome below the ecosystem table, with its remediation on failure. The Overall line then names both counts, pass or fail (e.g. `Overall: FAIL (0 of 2 ecosystems failed, 1 gate failed)`, `Overall: PASS (2 of 2 ecosystems passed, 1 gate passed)`), so it is clear whether a gate ran.

## For other skills referencing /toolchain:check

- **Command tables**: resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md), and read `context/<ecosystem>.md` for gotchas, including when embedding commands in an agent prompt.
- **Full verification**: invoke `/toolchain:check` or `/toolchain:check <ecosystem>` via the Skill tool.
- **Lint only**: invoke `/toolchain:lint` or `/toolchain:lint <ecosystem>` via the Skill tool; it resolves through the same ladder and also owns the `yaml` and `cross-cutting` surfaces.

## Next

- Overall `PASS`: /verification:confirm before committing.
- Overall `FAIL`: /testing:diagnose.

## Gotchas (cross-ecosystem)

- **CWD drift**, the most common source of false failures. Always use absolute paths.
- **A green exit that checked nothing.** A syntax-only command, or one that failed to start, is not a `pass`.
- **A green exit a retry earned.** Report `pass (flaky: N)`, never a plain `pass`.
- **Missing tool is never done.** `skip (tool missing: <tool>)` makes the Overall line `INCOMPLETE`, not `FAIL` and not `PASS`.
- **Multi-tool `check-cmd` atomicity.** When a `check-cmd` bundles a gated sub-tool with an unconditional one (bash's `shellcheck ... && shfmt -d <files>`), the opt-in gate cannot suppress just the gated part: both run whenever the unconditional one applies. The same opacity reaches the missing-tool rule: a sub-tool the ecosystem's probe never covers (python's `pyright` behind `uv`) is absent only at run time, so the Lint cell reports `FAIL`, not `skip`. Report what the runner did, never a skip it did not perform. Each affected `context/<ecosystem>.md` states the consequence.
- **Multiple projects in one ecosystem.** Ecosystems with an `anchor` scope to it; ecosystems with `project-discovery` patterns walk each discovered project root.
