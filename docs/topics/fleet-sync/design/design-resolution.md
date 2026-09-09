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

Exit: `0` at least one target; `3` nothing resolved (stderr lists every probe and the remedies: pass a directory, run `repo-fleet-hygiene:setup`, install ghq); `2` usage.

## 2. `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` (new)

Input: the resolver's argv passthrough plus `--dry-run` (default) | `--apply`, `--skip ENTRY`, `--skip-from FILE`. Repo discovery under a `root` reuses the audit's bounded walk semantics (depth bound, skip list, never descend symlinks/junctions, never re-enter nested repos) and dedups by `git rev-parse --git-common-dir`, retargeting linked worktrees to their main worktree.

Per-repo outcome record on stdout:

```text
<repo-path>	<outcome>	<action>	<detail>
```

- `outcome` ∈ `would-sync` | `synced` | `would-park` | `parked` | `skipped` | `failed`
- `action` ∈ `ff-pull` | `switch+ff-pull` | `park-branch` | `park-dirty-default` | `none`
- `detail` carries the source rung, the branch, the park path when any, and on skip/fail the git exit code and remedy

State machine per repo (default branch from `git ls-remote --symref origin HEAD` after `git fetch`):

| current branch | tree | unpushed | action |
|---|---|---|---|
| default | clean | — | `ff-pull` |
| default | dirty | — | `park-dirty-default`: stash `-u -m sync-park-<id>` → `worktree add -b park/<utc-date>-<short-sha> <path> HEAD` → apply by SHA in park → drop → `ff-pull` |
| other | clean | none | `switch+ff-pull` (no worktree) |
| other | clean | some | `park-branch`: `worktree add <path> <branch>` after `switch --detach` in canonical → `switch <default>` → `ff-pull` |
| other | dirty | any | `park-branch` with the stash round-trip as above, applied in the park |
| detached | any | — | `skipped` (detached HEAD; remedy printed) |

Failures that skip-and-report, never fall back: `pull --ff-only` exit 1 (dirty path would be overwritten) or 128 (diverged); dubious ownership; `worktree add` exit 128 (branch already checked out elsewhere); stash apply non-zero (stash entry retained, park left in place). Exit `0` when no repo failed, `1` when any did, `3` when the resolver found nothing.

Parking path comes from `worktree-create.sh` (§3), never computed locally.

## 3. `plugins/source-control/scripts/worktree-create.sh` (extend)

New flag `--existing-branch <name>`, mutually exclusive with `--name`/`--base-ref`. Runs `git worktree add <path> <name>` (no `-b`) with the same root ladder, containment guard, slug derivation, `.worktreeinclude` copy, and lock claim as the new-branch path. When git refuses because the branch is checked out elsewhere, the helper surfaces git's message and exits `4`; it never passes `--force`. Path is the sole stdout line, as today.

## Not re-derived

Configurability (the fleet conf and its setup skill already exist), observability (per-line records plus a `Summary:` line, the batch-common shape), and testability (co-located `<stem>.test.sh` driving the scripts against throwaway repos) follow the existing `repo-hygiene` batch verbs.
