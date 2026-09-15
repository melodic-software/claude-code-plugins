---
outcome: early-exit
tier: B
reason: bash CLI surfaces only, no runtime types; every contract was resolved by the interview (Q1–Q14) and is sketched below
---

# Design resolution — fleet-sync

Tier B early-exit. The "types" in this change are three shell contracts. Each is fixed here so `/planning:plan` plans against them rather than re-deriving them.

## 1. `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` (new, shared)

Input: argv mirroring the audit's grammar (`<dir>...`, `--root D`, `--repo D`, `--repos-from FILE|-`, `--config F`, `--project-dir D`, `--max-depth N`, `--skip NAME`) plus `--cwd D` (defaults to `$PWD`).

Output, one record per line on stdout, nothing else on stdout:

```text
target	<kind>	<path>	<rung>
```

- `kind` ∈ `root` | `repo`
- `path` is absolute, forward-slash, deduplicated
- `rung` ∈ `explicit` | `config` | `ghq` | `cwd-repo` | `cwd-ancestor` | `cwd-root`

Rung rules: explicit and config are additive; `ghq` and `cwd-*` fire only when explicit and config yield nothing. Conversation-named paths arrive as `explicit` because the SKILL.md instructs Claude to pass them as argv. Probe trace goes to stderr as `probe	<rung>	<what was checked>	<outcome>`.

Exit: `0` at least one target; `5` nothing resolved (stderr lists every probe and the remedies: pass a directory, run `repo-fleet-hygiene:setup`, install ghq); `2` usage.

Every git and `ghq` call the resolver makes runs through the audit's probe discipline: a fixed-argv allowlist, and a subshell that unsets the inherited git selectors and exports `GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat GIT_TERMINAL_PROMPT=0`. A resolver root that does not exist on disk is not scope.

## 2. `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` (new)

Input: the resolver's argv passthrough plus `--dry-run` (default) | `--apply`, `--yes`, `--skip ENTRY`, `--skip-from FILE`, `--worktree-root DIR`, `--data-root-file FILE`, `--no-fetch`. Dry-run fetches by default (it writes only refs and objects under `.git`, so the working tree, HEAD, the stash stack and the worktree list are all untouched); `--no-fetch` is the offline form, and a classification resting on a stale or missing tracking ref carries `provisional` in its record. Repo discovery under a `root` reuses the audit's bounded walk semantics (depth bound, skip list, never descend symlinks/junctions, never re-enter nested repos) and dedups by `git rev-parse --git-common-dir`, retargeting linked worktrees to their main worktree.

Per-repo outcome record on stdout:

```text
<repo-path>	<outcome>	<action>	<detail>
```

- `outcome` ∈ `would-sync` | `synced` | `would-park` | `parked` | `skipped` | `failed`
- `action` ∈ `ff-pull` | `switch+ff-pull` | `park-branch` | `park-dirty-default` | `none`
- `detail` carries the source rung, the branch, the park path when any, and on skip/fail the git exit code and remedy

State machine per repo (default branch from `git ls-remote --symref <remote> HEAD`):

| current branch | tree | unpushed | action |
|---|---|---|---|
| default | clean | — | `ff-pull` |
| default | dirty | — | `ff-pull` first; only when git refuses because a dirty path would be overwritten, `park-dirty-default`: the round-trip below onto a new `park/<utc yyyymmdd-HHMM>-<7-char sha>` branch, then `ff-pull` |
| other | clean | none | `switch+ff-pull` (no worktree) |
| other | clean | some | `park-branch`: the round-trip below onto the existing branch |
| other | dirty | any | `park-branch` with the stash step active |
| detached | any | — | `skipped` (detached HEAD; remedy printed) |

Park round-trip, in this order, with the canonical never detached: pre-flight (§3) → `git stash push -u -m sync-park-<uuid>` → capture the entry's SHA by marker → `git worktree add --detach <path> <branch>` (no `--force`) → `git stash apply --index <sha>` in the park → `git switch <default>` in the canonical, or `git switch -c <default> --track <remote>/<default>` when no local default branch exists → `git switch <branch>` in the park → re-find the stash by marker, assert the SHA at that index equals the captured SHA, then `git stash drop stash@{n}` (drop refuses a raw SHA) → `ff-pull`. A failure before the canonical switch restores with `git stash apply --index <sha>` in the canonical, drops by the same discipline, reports `failed`, and removes the park only when this run created it and it is clean. A failure after the canonical switch reports `failed` and names the park path where the work now lives.

Post-condition asserts run after every mutating step (the symbolic ref of HEAD equals the target, `status --porcelain` matches the expected shape); a mismatch is `failed`.

The canonical checkout is never left detached. `park-dirty-default` is attempted as a plain `ff-pull` first and becomes a park only when git refuses because a dirty path would be overwritten.

Failures that skip-and-report, never fall back: `pull --ff-only` exit 1 (dirty path would be overwritten, and the park attempt that follows also failed) or 128 (diverged); `ls-remote` or `fetch` failure or timeout; dubious ownership; `worktree add` exit 128 (branch already checked out elsewhere); stash apply non-zero (stash entry retained, park left in place). Exit `0` when no repo failed, `2` usage, `3` confirmation-gate abort or non-interactive `--apply` without `--yes`, `4` when any repo failed, `5` when the resolver found nothing.

Every network verb (`ls-remote`, `fetch`, `pull`) runs under the audit's env pinning and its timeout wrapper; a timeout is `failed` with the remedy.

Remote selection per repo: the current branch's configured remote, else `origin`, else the sole remote; none of those and the repo is `skipped`. The default branch is `git ls-remote --symref <remote> HEAD`.

Parking path comes from the sync-owned primitive (§3), never from another plugin.

## 3. Parking primitive (sync-owned)

Parking lives inside the sync skill (`sync-fleet.sh` or a sibling `lib/` file beside it). It is not a call into `source-control`: installed plugins live in separate versioned cache directories, `docs/PLUGIN-PHILOSOPHY.md` forbids reaching into a sibling plugin's files, and `worktree-create.sh`'s root-ladder rungs 3 and 4 are caller-supplied from `source-control`'s own plugin option and data directory, which `repo-fleet-hygiene` cannot read. Invoking `/source-control:worktree create` per park is also out, because that path terminates in `EnterWorktree`.

Root ladder, in order: explicit `--worktree-root <dir>`; then the `melodic.worktreeroot` git config key read from the target repository with includes on, per `plugins/source-control/reference/worktree-root-convention.md`, which is the artifact contract between the two plugins; then `${CLAUDE_PLUGIN_DATA}/worktrees` supplied through a file the SKILL.md writes, mirroring the existing `--data-root-file` pattern; else refuse with the remedy.

Directory name is `<root>/<owner>-<repo>-<slug>`.

Pre-flight, run before any mutation: the root resolves; the root is not inside any repository (containment); on Windows the root is on the same drive as the repository, and a cross-drive root is `skipped` with the config remedy; the park path is free; the repository has no in-progress merge, rebase, or cherry-pick; the repository is not a submodule superproject.

Each park is locked with a park-specific reason, `parked by repo-fleet-hygiene:sync on <host> at <utc>; git worktree unlock <path> to remove`, and the unlock remedy is printed in the record.

## 4. Exit codes across the plugin's verbs

| Code | `audit` | `apply` | `sync` | `resolve-fleet-scope.sh` |
|---|---|---|---|---|
| 0 | success | success | success | at least one target |
| 2 | usage, and nothing-resolved today | usage | usage | usage |
| 3 | — | gate abort, or non-interactive `--apply` without `--yes` | same | — |
| 4 | — | mutations failed | one or more repos failed | — |
| 5 | — | — | nothing resolved | nothing resolved |

The audit's use of 2 for nothing-resolved is pre-existing and stays; changing it is out of scope for this work and would break the two consumers that assert it.

## Not re-derived

Configurability (the fleet conf and its setup skill already exist), observability (per-line records plus a `Summary:` line, the batch-common shape), and testability (co-located `<stem>.test.sh` driving the scripts against throwaway repos) follow the existing `repo-hygiene` batch verbs.
