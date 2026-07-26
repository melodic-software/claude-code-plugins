---
name: check
description: "Run build, test, and lint verification for changed files, auto-detecting affected ecosystems (.NET, Python, TypeScript, Bash, PowerShell, Markdown) from git status, with the consuming project's own documented commands overriding portable defaults. Use after any code edit or for 'does it compile' / 'run tests' checks; for lint-only use /toolchain:lint, for full outcome verification use /verification:confirm."
user-invocable: true
argument-hint: "[ecosystem] (e.g., /toolchain:check dotnet, /toolchain:check python, /toolchain:check all — default: auto-detect from git status)"
shell: bash
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

Available ecosystem filters are the ecosystems `/toolchain:check` covers: `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go` (resolved per the ladder). Common aliases: `ts`/`node` → `typescript`, `shell` → `bash`, `ps`/`pwsh` → `powershell`, `md` → `markdown`, `golang` → `go`. Literal `all` runs every covered ecosystem. The lint-only `yaml` and `cross-cutting` surfaces are **not** run by `/toolchain:check` — use `/toolchain:lint` for those.

## Ecosystem detection

Each ecosystem declares a list of `globs` that classify changed files into that ecosystem (resolved per the ladder — consumer `.claude/ecosystems/<ecosystem>.yaml` when present, else the bundled default). The skill matches `git status --porcelain` output against each covered ecosystem's `globs` to determine which ecosystems are affected. `/toolchain:check` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`; the lint-only `yaml` and `cross-cutting` surfaces are `/toolchain:lint`'s (in particular `cross-cutting`'s `**` glob is never matched here).

For ecosystem-specific gotchas, reference files, and primary-source detail, read the corresponding context file:

- [context/dotnet.md](context/dotnet.md) — .NET build, test, format
- [context/sarif.md](context/sarif.md) — Roslyn SARIF output, jq parser patterns, AI consumption
- [context/python.md](context/python.md) — Python lint, format, test
- [context/typescript.md](context/typescript.md) — TypeScript compile, test, lint
- [context/bash.md](context/bash.md) — ShellCheck, shfmt
- [context/powershell.md](context/powershell.md) — PSScriptAnalyzer
- [context/go.md](context/go.md) — Go build, test, lint, module discovery

When invoked as a task (`/toolchain:check`), detect from `git status --porcelain`. When referenced by another skill, use the file list that skill provides.

## Workflow (when invoked as /toolchain:check)

### 0. Resolve repo root

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

All commands use absolute paths. Never `cd` and lose context.

### 1. Detect ecosystems

If `$ARGUMENTS` specifies an ecosystem, use it. If `all`, run every covered ecosystem. Otherwise, classify changed files from `git status --porcelain` against each covered ecosystem's `globs` (resolved per the ladder; `/toolchain:check` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`). Skip any ecosystem whose resolved `enabled` is `false` (a consumer opt-out) — excluded even under `all`.

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

**Opt-in gate (lint phase only)**: before running an ecosystem's `check-cmd`, evaluate its resolved `opt-in` condition (if present) against the repo. Build and test always run regardless of `opt-in` — only the lint phase is gated, since compiling and testing don't depend on style configuration.

This binary gate applies cleanly when `opt-in` describes ONE condition governing the whole `check-cmd` (e.g. dotnet, python, go): unmet → report the ecosystem's Lint column as `skip (opt-in unmet: <condition, ≤10 words>)` — visible, not silently omitted — and do not run `check-cmd`. Met → run `check-cmd` normally.

When `opt-in` instead describes MULTIPLE independent per-tool conditions bundled into one opaque command string (e.g. bash's `"shellcheck always applies to shell files; shfmt only when .editorconfig declares shell style"`, where `check-cmd` is `shellcheck ... && shfmt -d <files>`), this gate does NOT apply — `check-cmd` is a single opaque string (per the ecosystem-commands contract) with no way to run one sub-tool's portion without the other. Run `check-cmd` as before (unchanged from prior behavior) and report its real output; do not attempt a partial skip. See Gotchas below for the known atomicity limitation this leaves open.

An opt-in-unmet skip (single-condition case) counts toward the table's total ecosystem count but never toward the FAIL count, the same precedent as a missing-tool skip. This is ecosystem-generic (reads the resolved `opt-in` key), not dotnet-specific — it applies to every current and future single-condition opt-in-bearing ecosystem `/toolchain:check` covers. CI-parity gates (below) are unaffected — they run independent of `check-cmd`.

**CI-parity gates (resolved `gates` array).** After an affected ecosystem's build → test → lint, iterate its resolved `gates` array (§1.5 — bundled default or consumer file, per the ladder). Gates cover the CI-parity checks plain build / test / lint don't catch: lockfile drift, generated-artifact freshness, schema regeneration. For each gate:

- **Fire condition** — `trigger-globs` narrows a *change-driven* run. Under auto-detection (§1), run the gate only when ≥1 changed file matches, matched against the **full** changed-files set (not the ecosystem-scoped subset — a gate's trigger files need not classify into the ecosystem's own `globs`); no match → the gate does not fire. If `trigger-globs` is omitted, run whenever the ecosystem runs.
- **Explicit scope overrides the narrowing** — when `$ARGUMENTS` names a scope (`/toolchain:check all` or `/toolchain:check <ecosystem>`), every gate of a selected ecosystem fires regardless of `trigger-globs`. The user asked to verify that scope, not to narrow by what changed, and the ecosystem's own `build-cmd`/`test-cmd`/`check-cmd` already run in full there — leaving gates change-narrowed would make `check all` on a clean tree, the exact command §1 tells the user to run for full-repo verification, pass a committed-but-untidy `go.mod`. This is also the only way to force a gate without manufacturing a matching change.
- **Reachability** — a gate is subordinate to its ecosystem's run (per the ecosystem-commands schema: `trigger-globs` "run the gate only when a changed file matches; omit to run whenever the ecosystem runs"), so `trigger-globs` narrows *within* a run and never selects an ecosystem. Under auto-targeting the ecosystem must first be affected by its own `globs` (§1); a gate whose `trigger-globs` alone match a changed file is reached via `/toolchain:check <ecosystem>` or `/toolchain:check all`. This is settled, not a parked default: to make a cross-ecosystem trigger select its ecosystem under auto-targeting, add the trigger pattern to that ecosystem's own `globs`.
- **Independent of the build/test/lint short-circuit** — a fired gate runs even when this ecosystem's build, test, or lint already failed and stopped (line above). Gates mirror CI checks that are independent of build success (a lockfile or `go mod tidy` gate is meaningful whether or not the build compiled), so a failed earlier phase never suppresses them.
- **Run** `gate.cmd` (an opaque shell string — substitute the same placeholders as other commands: `<files>`, resolved anchor, etc.) with absolute paths, from the **same execution location the ecosystem's own build/test/lint use** (§2 placeholders, and Gotchas' "Multiple projects in same ecosystem"): once per resolved `<project-dir>` for a `project-discovery` ecosystem, from the `anchor`'s directory for an `anchor` ecosystem, and from `$REPO_ROOT` only when neither is defined. This matters for the bundled `go.yaml` `go-mod-tidy-drift` gate: `go mod tidy -diff` is inherently per-module, so a `project-discovery: ["go.mod"]` monorepo must run it from each `go.mod` root — a `$REPO_ROOT`-only run falsely fails when the sole module is nested (`go.mod file not found`) and never checks drift in nested modules when a root module also exists. The **fire condition** above stays repo-wide (`trigger-globs` vs the full changed-files set decides *whether* the gate runs); only the execution location is per-project. When a gate `cmd` uses `<files>`, it expands to that project's scoped changed-files subset, exactly as for the ecosystem's other commands (§2). A gate cannot override this — see Gotchas' "Gate execution scope is the ecosystem's, not the gate's" for the limitation this leaves open for a repo-wide gate under a `project-discovery` ecosystem.
- **Tool presence** — as with `check-cmd`, if the gate's tool is missing from `PATH`, report `skip` (reuse the ecosystem's `install-hint`) — never `FAIL`.
- **Version floor** — a tool that is present but too old for the gate's invocation is an environment capability gap, not project drift, so it reports `skip (unsupported: <tool + capability, ≤10 words>)` with the `install-hint` rather than a false `FAIL`. The bundled `go.yaml` `go-mod-tidy-drift` gate has one: `go mod tidy -diff` needs Go 1.23+, so a Go 1.22 toolchain must skip rather than fail every `*.go`/`go.mod`/`go.sum` change. **A rejected invocation is not by itself evidence of a version floor** — a typo in a consumer's `gate.cmd` (misspelled flag, wrong subcommand) is rejected identically, and skipping it would leave a malformed gate silently unenforced. So the skip requires the mismatch to be **positively established**, either by the tool naming its own minimum in the error, or by a minimum documented for that gate (the gate's `remediation`, the ecosystem's `notes`, or `context/<ecosystem>.md`) that the tool's reported version — queried directly, e.g. `go version` — falls below. Unexplained rejection → `FAIL`, with the rejection text shown so the typo is visible. Every other non-zero exit (a malformed manifest, a network failure, real drift) is likewise a `FAIL`.
- **Outcome** — report `pass`/`FAIL` by name. On `FAIL`, surface `gate.remediation`. A fired gate that fails is a real failure and **counts toward the run's FAIL verdict** (unlike opt-in/missing-tool skips).

Gates resolve through the ladder like every other key: a bundled default may ship one (e.g. `go.yaml`'s `go-mod-tidy-drift`), and a consumer declares its own in its tracked `.claude/ecosystems/<ecosystem>.yaml` `gates` array (e.g. the `nuget-lockfile-drift` shape in `docs/conventions/ecosystem-commands/examples/dotnet.yaml`).

**Convention-documented gates still run.** The `gates` array is the declaration form this skill can resolve, report by name, and layer per the ladder — but it is not the only place a consuming project states its CI-parity checks. When the project documents extra local checks in its own conventions (its `CLAUDE.md`, `.claude/rules/`, or a commands reference) rather than in a `gates` array, run those too, by the same rules above: fire on their stated trigger files, run after build → test → lint and independent of that short-circuit, report by name with the project's own remediation, and count a failure toward the verdict. A project that documented its gates in prose keeps them; declaring them in `.claude/ecosystems/<ecosystem>.yaml` is the preferred form because it makes them structured, layerable, and machine-checkable, not a precondition for running them.

For ecosystem-specific gotchas (xUnit `--nologo` trap, `dotnet test --project`, etc.), read the corresponding `context/<ecosystem>.md` file.

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

Use `pass`, `FAIL`, `skip` (tool missing), `skip (opt-in unmet: ...)` (config condition not met), `skip (unsupported: ...)` (gates only — the installed tool's version is below the gate's documented floor), or `—` (not applicable — for ecosystems where the corresponding command is null in the ecosystem config). Show failing command output below the table.

If any CI-parity gates fired, summarize each by name + outcome below the per-ecosystem block, with the remediation pointer on failure. A fired gate that failed flips Overall to `FAIL` and is counted in it — including when every ecosystem's build/test/lint cell passed (e.g. `Overall: FAIL (0 of 2 ecosystems failed, 1 gate failed)`). The Overall line names both counts whenever a gate fires, pass or fail — a fired-and-passed gate still reports its count (e.g. `Overall: PASS (2 of 2 ecosystems passed, 1 gate passed)`), so the report is unambiguous about whether a gate ran.

## For other skills referencing /toolchain:check

When composing `/toolchain:check` from another skill (like `/verification:confirm` or `/toolchain:lint`):

- **To get command tables**: resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md`](${CLAUDE_PLUGIN_ROOT}/reference/resolution-ladder.md) — consumer `.claude/ecosystems/<ecosystem>.yaml` wins, bundled defaults at `${CLAUDE_PLUGIN_ROOT}/reference/ecosystems/` are the fallback — or the relevant `context/<ecosystem>.md` for gotchas and prose detail
- **To run full verification**: invoke `/toolchain:check` or `/toolchain:check <ecosystem>` via the Skill tool
- **To run lint-only checks**: invoke `/toolchain:lint` or `/toolchain:lint <ecosystem>` (it resolves through the same ladder and additionally owns the `yaml` and `cross-cutting` surfaces)
- **To embed commands in agent prompts**: resolve per the ladder AND read the corresponding `context/<ecosystem>.md` for gotchas

## Gotchas (cross-ecosystem)

- **CWD drift** — the #1 source of false failures. Always use absolute paths
- **Missing tools** — report as `skip` with reason, not as failure (e.g., `uv` not installed)
- **Opt-in unmet** — report as `skip (opt-in unmet: ...)` with the condition, not as failure and not silently omitted (e.g., dotnet with no C#-relevant `.editorconfig`)
- **Multi-tool `check-cmd` atomicity** — when a multi-tool ecosystem's `check-cmd` bundles a gated sub-tool and an unconditional sub-tool in one shell string (e.g. bash's `shellcheck ... && shfmt -d <files>`), the opt-in gate cannot suppress just the gated sub-tool's contribution — both run whenever the unconditional sub-tool's condition holds, per the ecosystem-commands contract's own "opaque shell string" rule. Splitting a multi-tool `check-cmd` into separately gateable ecosystem keys would need a schema change; not addressed here
- **Gate execution scope is the ecosystem's, not the gate's** — a gate runs from wherever its ecosystem's own build/test/lint run (§2), so under a `project-discovery` ecosystem it runs once per discovered project root. That is right for a per-project gate (`go mod tidy -diff`) but wrong for a repo-wide one (a protobuf-generation or schema-freshness check under `go`), which then runs redundantly or fails in project roots lacking its config. A gate cannot request `$REPO_ROOT`: the gate item in `docs/conventions/ecosystem-commands/ecosystem.schema.json` carries no execution-scope key, and adding one would need a schema change; not addressed here. Declare such a gate under an ecosystem without `project-discovery` until then
- **Multiple projects in same ecosystem** — ecosystems with an `anchor` use that as the scoping anchor; ecosystems with `project-discovery` patterns walk each discovered project root
