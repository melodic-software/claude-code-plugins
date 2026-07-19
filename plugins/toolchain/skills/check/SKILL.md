---
name: check
description: "Run build, test, and lint verification for changed files, auto-detecting affected ecosystems (.NET, Python, TypeScript, Bash, PowerShell, Markdown) from git status, with the consuming project's own documented commands overriding portable defaults. Use after any code edit or for 'does it compile' / 'run tests' checks; for lint-only use /toolchain:lint, for full outcome verification use /verification:confirm."
user-invocable: true
argument-hint: "[ecosystem] (e.g., /toolchain:check dotnet, /toolchain:check python, /toolchain:check all — default: auto-detect from git status)"
---

## Pre-computed context

Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo ""`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

Detects affected ecosystems from changed files and runs each one's build → test → lint. Serves two roles:

1. **Task skill** — `/toolchain:check` runs build verification for changed files. `/toolchain:check dotnet` targets one ecosystem
2. **Reference skill** — its sibling `/toolchain:lint`, the `verification` plugin's `/verification:confirm` (when installed), and verification agents compose this for detection and command resolution instead of baking their own tables

**The command surface is resolved, not hardcoded.** Both `/toolchain:check` and `/toolchain:lint` resolve each ecosystem's build/test/lint commands through the shared four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md): the consuming repo's tracked `.claude/ecosystems/<ecosystem>.yaml` is authoritative when present; the plugin's bundled portable defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the rung-4 fallback. The consumer's file always wins.

## Arguments

`$ARGUMENTS` — optional ecosystem filter. If provided, run only that ecosystem. If omitted, auto-detect from changed files.

Available ecosystem filters are the ecosystems `/toolchain:check` covers: `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown` (resolved per the ladder). Common aliases: `ts`/`node` → `typescript`, `shell` → `bash`, `ps`/`pwsh` → `powershell`, `md` → `markdown`. Literal `all` runs every covered ecosystem. The lint-only `yaml` and `cross-cutting` surfaces are **not** run by `/toolchain:check` — use `/toolchain:lint` for those.

## Ecosystem detection

Each ecosystem declares a list of `globs` that classify changed files into that ecosystem (resolved per the ladder — consumer `.claude/ecosystems/<ecosystem>.yaml` when present, else the bundled default). The skill matches `git status --porcelain` output against each covered ecosystem's `globs` to determine which ecosystems are affected. `/toolchain:check` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`; the lint-only `yaml` and `cross-cutting` surfaces are `/toolchain:lint`'s (in particular `cross-cutting`'s `**` glob is never matched here).

For ecosystem-specific gotchas, reference files, and primary-source detail, read the corresponding context file:

- [context/dotnet.md](context/dotnet.md) — .NET build, test, format
- [context/sarif.md](context/sarif.md) — Roslyn SARIF output, jq parser patterns, AI consumption
- [context/python.md](context/python.md) — Python lint, format, test
- [context/typescript.md](context/typescript.md) — TypeScript compile, test, lint
- [context/bash.md](context/bash.md) — ShellCheck, shfmt
- [context/powershell.md](context/powershell.md) — PSScriptAnalyzer

When invoked as a task (`/toolchain:check`), detect from `git status --porcelain`. When referenced by another skill, use the file list that skill provides.

## Workflow (when invoked as /toolchain:check)

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

All commands use absolute paths. Never `cd` and lose context.

### 1. Detect ecosystems

If `$ARGUMENTS` specifies an ecosystem, use it. If `all`, run every covered ecosystem. Otherwise, classify changed files from `git status --porcelain` against each covered ecosystem's `globs` (resolved per the ladder; `/toolchain:check` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`). Skip any ecosystem whose resolved `enabled` is `false` (a consumer opt-out) — excluded even under `all`.

If the working tree is clean, fall back to the branch diff so checkpoint-committed work still gets classified (the common pre-PR case: every green block was already committed). Resolve the default branch by **detection, not assumption** — never a hardcoded `main`/`master` — and assign it before use:

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

The loop probes candidate remotes in priority order — the remote the current branch tracks (`branch.<name>.remote`) first, then `origin` if present, then the rest — and selects the first one whose default branch resolves to a locally available tracking ref, never a hardcoded remote name. This handles an unpushed feature branch (no tracking remote) in a repo cloned with a different remote name (e.g. `git clone -o vendor`), and skips a remote that was added but never fetched (its default branch has no local `refs/remotes/<remote>/<branch>` to diff against) in favor of a later remote that does — the candidate is accepted only when `git rev-parse` confirms the tracking ref exists locally. Each candidate's default branch comes from that remote's own `HEAD` (not the current branch's upstream, which on a pushed feature branch points at the feature branch itself and would make `merge-base` equal `HEAD`, yielding an empty diff), falling back to a `git ls-remote --symref` query when the local `HEAD` symref is absent. `merge-base` is taken against the fully-qualified remote-tracking ref `refs/remotes/$REMOTE/$DEFAULT_BRANCH`, which resolves without a local branch of that name and — like the `rev-parse` verify — cannot be misparsed as an option when the remote name begins with a dash (`git clone --origin=-x`); the `git ls-remote` probe terminates option parsing with `--end-of-options` for the same reason. If no candidate yields a locally available default branch, skip the branch-diff path rather than guessing. A caller passing an explicit changed-file list (e.g. `/verification:confirm`) overrides both detection paths.

If neither path yields changes and no `$ARGUMENTS`: report "No changes found (working tree clean, no branch diff vs the default branch). Use `/toolchain:check all` to verify the full repo, or `/toolchain:check <ecosystem>` for a specific ecosystem." and exit.

**Conversation-aware targeting**: when the conversation has been working with specific files/projects, scope the build to what was touched — don't rebuild the whole scope for a single-project change. The ecosystem config's `anchor` field provides the default scoping anchor for ecosystems with a canonical entry point; substitute a narrower project file when changes are confined to one project. For .NET specifically: use the specific `.csproj` when changes are in one project, use the solution file when changes span multiple projects or touch shared files (`.props`, `.targets`, solution file).

### 1.5 Resolve each ecosystem's command surface

For each affected ecosystem, resolve its command surface (`globs`, `build-cmd`, `test-cmd`, `check-cmd`, `fix-cmd`, `anchor`, `project-discovery`, `install-hint`, `gates`, `notes`) through the four-rung ladder in [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md):

1. Consumer `.claude/ecosystems/<ecosystem>.yaml` (+ `.local.yaml` overlay, `~/.claude/ecosystems/` user-global, additive per key) → authoritative.
2. Absent → infer from the repo's build files and offer to persist via `/toolchain:setup`.
3. Cannot infer → ask; offer to persist.
4. Otherwise → the bundled default at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/<ecosystem>.yaml`.

A malformed consumer file warns and degrades to rung 2 — never a hard stop.

### 2. Run checks

For each affected ecosystem, use the resolved `build-cmd`, `test-cmd`, and `check-cmd`. Null commands are skipped (no build step / no test framework / no lint).

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

## For other skills referencing /toolchain:check

When composing `/toolchain:check` from another skill (like `/verification:confirm` or `/toolchain:lint`):

- **To get command tables**: resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) — consumer `.claude/ecosystems/<ecosystem>.yaml` wins, bundled defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the fallback — or the relevant `context/<ecosystem>.md` for gotchas and prose detail
- **To run full verification**: invoke `/toolchain:check` or `/toolchain:check <ecosystem>` via the Skill tool
- **To run lint-only checks**: invoke `/toolchain:lint` or `/toolchain:lint <ecosystem>` (it resolves through the same ladder and additionally owns the `yaml` and `cross-cutting` surfaces)
- **To embed commands in agent prompts**: resolve per the ladder AND read the corresponding `context/<ecosystem>.md` for gotchas

## Gotchas (cross-ecosystem)

- **CWD drift** — the #1 source of false failures. Always use absolute paths
- **Missing tools** — report as `skip` with reason, not as failure (e.g., `uv` not installed)
- **Multiple projects in same ecosystem** — ecosystems with an `anchor` use that as the scoping anchor; ecosystems with `project-discovery` patterns walk each discovered project root
