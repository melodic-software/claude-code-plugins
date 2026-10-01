# repo-fleet-hygiene

`repo-fleet-hygiene` is the machine-wide coordination layer for repository hygiene. Its job is to
discover canonical repositories across the machine, collect fleet-scale Git/GitHub evidence, roll
that evidence up, and hand an action plan to the per-repository owners. It does not replace those
owners or reimplement their cleanup decisions.

The currently shipped audit reports:

- local branches whose matching GitHub pull request is merged;
- remote-tracking heads that still exist on origin after a GitHub merge, because
  `delete_branch_on_merge` is not enabled or was blocked. Enabling that setting is complementary to
  this visibility rather than a substitute for it, and this plugin never changes repository
  settings;
- remote heads with no pull request ever, or only closed unmerged pull requests, as gated deletion
  candidates (see [Remote branch deletion](#remote-branch-deletion));
- merged-PR, missing, prunable, or administratively mismatched worktree registrations;
- linked worktrees that do not conform to the configured worktree root (or placement when unset); and
- GitHub repositories whose configured remote resolves to a different owner or name.

The plugin is deliberately **read-only by default**. `/repo-fleet-hygiene:audit` never fetches,
prunes, repairs, deletes, checks out, or rewrites anything. Every finding names its evidence,
confidence, disposition, and exact target. Two verbs mutate, each only behind `--apply` and one
confirmation: `/repo-fleet-hygiene:apply --plan-file <path> [--apply] [--yes] [--remote-branches]` consumes the audit's
action-plan JSON (see [Fleet cleanup plan](#fleet-cleanup-plan)), and `/repo-fleet-hygiene:sync`
fast-forwards canonical checkouts (see [Sync](#sync)). Per-repository owners remain available for
interactive work:

- `/repo-hygiene:clean git` for a local-branch audit and its own confirmation gate;
- `/source-control:worktree cleanup --dry-run` for worktree cleanup planning; and
- `git worktree repair` only as a manually reviewed option for an administrative mismatch.

## Fleet capability contract

The epic's fleet architecture is intentionally split from the current implementation status:

| Capability | Owner | Availability in this release |
|---|---|---|
| Bounded repository discovery (bare path, drive root, `--root`, `--repo`, config rungs) and canonical-checkout resolution | `repo-fleet-hygiene` | Shipped |
| No-argument scope: the ladder in [audit's SKILL.md](skills/audit/SKILL.md) (`--named` paths, `ghq root --all`, an ancestor directory of the working directory's checkout holding 2 or more repositories, that checkout alone, else exit 3) | `repo-fleet-hygiene` | Shipped for `audit` and `sync`. Not shipped: agent state and a bounded machine sweep as rungs. Remaining contract work, not an open issue |
| Cross-repository GitHub merge and repository-identity evidence | `repo-fleet-hygiene` | Shipped |
| Per-repository worktree status, stranded-work classification, and cleanup | `/source-control:worktree` | Delegated; fleet-local reclaimability was retired in [#2605](https://github.com/melodic-software/claude-code-plugins/issues/2605) |
| Per-repository branch, cache, build, and deletion triage | `/repo-hygiene:clean` | Delegated |
| Per-repository verdicts, target deduplication, and a machine-readable rollup artifact | `repo-fleet-hygiene` | Shipped |
| One fleet cleanup-plan handoff consuming that artifact | `repo-fleet-hygiene:apply` (owns batched merged-local-branch deletion; worktree cleanup in plan order) | Shipped |
| Conformance against the configured worktree root | `repo-fleet-hygiene`, reading the convention owned by `source-control` | Shipped |
| Complete exact branch merge evidence via GraphQL | `repo-fleet-hygiene` | Shipped |
| Merged remote-branch reporting and its separate safety gate | `repo-fleet-hygiene` | Tracked by [#2607](https://github.com/melodic-software/claude-code-plugins/issues/2607); follow-up PR [#2645](https://github.com/melodic-software/claude-code-plugins/pull/2645) |

Rows marked "not yet shipped" are contracts, not commands this version accepts. Their linked child
issues become the shipping record when merged; until then, the audit preserves the current detailed
report and exact per-repository handoffs.

## Actions

| Skill | Purpose |
|---|---|
| `/repo-fleet-hygiene:audit` | Scan one repository, explicit repositories, or repository-tree roots and render a fleet report (read-only; writes an action-plan JSON) |
| `/repo-fleet-hygiene:apply` | Dry-run or apply a prior action-plan JSON behind one fleet confirmation (`--apply` + confirm / `--yes`) |
| `/repo-fleet-hygiene:sync` | Dry-run or apply a fast-forward of every canonical checkout onto the remote default branch; dirty work is parked in a linked worktree (`--apply` + confirm / `--yes`) |
| `/repo-fleet-hygiene:setup` | `check` inspects the optional tracked fleet configuration read-only; `apply` creates or updates it without touching user settings |

## Quick start

Audit the current project repository explicitly (no fleet config required):

```text
/repo-fleet-hygiene:audit --repo <checkout>
```

A bare `/repo-fleet-hygiene:audit` with neither CLI scope nor `fleet.root` / `fleet.repo` in a
resolved config follows the no-scope ladder in [audit's SKILL.md](skills/audit/SKILL.md) and exits 3
naming every rung when none resolves.

Audit one or more repository-tree roots:

```text
/repo-fleet-hygiene:audit --root <repo-root>/github.com --root <other-root>/internal
```

Audit exact repositories without recursive discovery:

```text
/repo-fleet-hygiene:audit --repo <repo-root>/github.com/acme/api --repo <repo-root>/github.com/acme/web
```

Config resolution is a whole-file precedence ladder: explicit `--config <path>`, else
`.claude/repo-fleet-hygiene.conf` in the consumer project, else the user-global
`~/.claude/repo-fleet-hygiene.conf` (a machine-scoped fleet config that applies from every
project). The audit report header names which config was consumed. Explicit CLI roots/repos are
additive.

## Sync

`/repo-fleet-hygiene:sync` puts each canonical checkout on the remote's default branch and
fast-forwards it. Bare invocation prints a dry-run plan and changes nothing.

```text
/repo-fleet-hygiene:sync
/repo-fleet-hygiene:sync --apply
/repo-fleet-hygiene:sync --apply --yes
```

`--yes` skips the script's prompt, not the operator: pass it only after reading the dry-run plan and
agreeing to it. `--apply` without a terminal and without `--yes` exits 3. A dirty checkout is parked
in a linked worktree by the helper named with `--worktree-create <path to worktree-create.sh>`;
`--worktree-root <dir>` optionally overrides the root the helper resolves. Without
`--worktree-create`, a dirty checkout is skipped and reported. Every plan and skipped line ends with
`rung=<rung>` naming the scope source that produced the repository (`repo`, `repos-from`, `root`,
`config`, `named`, `ghq`, `cwd`, `ancestor`). See [the sync skill](skills/sync/SKILL.md) for the
scope ladder and skip rules.

## Fleet cleanup plan

`/repo-fleet-hygiene:apply` consumes the machine-readable action-plan JSON from
[#2608](https://github.com/melodic-software/claude-code-plugins/issues/2608) /
[#2609](https://github.com/melodic-software/claude-code-plugins/issues/2609); it never scrapes the
human report.

```text
/repo-fleet-hygiene:apply --plan-file <path-from-audit>
/repo-fleet-hygiene:apply --plan-file <path-from-audit> --apply
/repo-fleet-hygiene:apply --plan-file <path-from-audit> --apply --yes
```

The apply verb:

1. validates `schema_version: 1` and preserves repository-qualified targets;
2. owns batched `merged-local-branch` deletion (repo-hygiene branch deletion stays interactive) and
   cleans merged/prunable/missing worktrees in the plan's declared order;
3. shows one fleet plan and requires one explicit confirmation (or `--yes`) before any mutation; and
4. re-derives mutable branch/worktree OIDs at execution time. Tip drift skips fail-closed.

Audit remains read-only. A `HIGH` finding is never itself permission to delete; only `:apply
--apply` after confirmation (or `--yes`) mutates. Do not add an execute flag to `audit-fleet.sh`.

### Remote branch deletion

Remote deletion is off by default: plain apply never contacts a remote, and a plan's
`delete-remote-branches` rows are skipped. The audit plans such rows only for `unmerged-remote-branch`
findings of class `never-pr` (no pull request ever used the branch) or `closed-unmerged` (every pull
request closed unmerged, one at the live tip). A branch whose pull request merged
(`merged-remote-branch`) is never planned for deletion.

```text
apply-plan.sh --plan-file <path-from-audit> --apply --remote-branches
```

- Each branch has its own `[y/N]` prompt naming repository, remote, branch, class, and tip. `--yes`
  never answers it, and a session without a terminal deletes nothing at all, local rows included.
  `/repo-fleet-hygiene:apply --remote-branches` gives the script no terminal, so from the skill it only
  previews; run the script in your own terminal to delete.
- Live state is re-read first. Drift in the `git ls-remote` tip, an already-gone head, the remote's
  default branch, a remote whose fetch or push URL no longer names the audited repository, or a
  pull request that is now open, merged, or missing its audited class (checked with `gh pr list`)
  skips the row. So does a failed `gh` call.
- The tip is appended to `<plan-file>.tip-ledger` before the push, with a restore command
  (`git -C <repo> push <remote> <tip>:refs/heads/<branch>`). The push carries a lease on that exact
  tip. The restore command works while the tip object is still in the local repository; after a
  delete it is unreachable, so `git gc` removes it once `gc.pruneExpire` (two weeks by default)
  passes.

## Configuration

Configuration uses Git's own config-file grammar, so no JSON parser or third-party runtime is required.
Relative paths resolve from the configuration file's directory. Repeat `root` and `repo` as needed:

```gitconfig
[fleet]
    root = ../../repos/github.com
    repo = ../../special/exact-checkout
    maxDepth = 5

# Key by the remote identity observed before GitHub redirect resolution.
# This is the supported escape hatch for manager-owned/non-obvious canonical checkouts.
[canonical "github.com/acme/dotfiles"]
    path = ../../../.local/share/chezmoi
```

Resolution order is explicit `--canonical REMOTE=PATH`, config `[canonical "REMOTE"]`, then
`git rev-parse --show-toplevel` on the discovered checkout. `REMOTE` is the normalized
`github.com/owner/repository` identity from the selected fetch remote. A canonical override changes
where local branches and worktrees are read; it does not suppress remote-migration detection.

The selected remote is `origin` when present, otherwise the sole configured remote. Ambiguous or
non-GitHub remotes are reported as unknown rather than guessed. This is GitHub-only v1; GitHub
Enterprise and other forges are not contacted.

## Confidence and safety

| Confidence | Meaning | Cleanup disposition |
|---|---|---|
| `HIGH` | Direct authoritative evidence agrees (for example, a GitHub merged PR head OID equals the local branch tip) | Candidate for the named per-repo tool's own dry run/gate |
| `MEDIUM` | Direct evidence identifies a condition, but another fact prevents safe cleanup (for example, commits after the merged PR head) | Manual review |
| `LOW` | Local or indirect evidence only | Informational; never a cleanup candidate |
| `UNKNOWN` | A prerequisite, permission, identity, or API result is unavailable/ambiguous | Investigate; never infer absence or safety |

Absolute local paths appear only in local report output. The only network calls are authenticated,
read-only `gh` queries to `github.com`; no report content, file content, or git object is uploaded.
When `gh` is absent or unauthenticated, the Git/worktree portion still runs and all GitHub-backed
claims become `UNKNOWN`. Each `gh` invocation has a 30-second deadline followed by a five-second
TERM-to-KILL grace; a timeout degrades only the affected GitHub evidence instead of stalling the
fleet. GNU `timeout`/`gtimeout` is used when its kill-after capability is available, with a Bash
watchdog fallback on other supported platforms.

Every Git probe disables lazy fetching and optional locks, so a read cannot contact a promisor remote
or refresh repository metadata as a side effect. Git and `gh` execution is fail-closed: the collector
accepts only its documented command, option, operand, and environment shapes. A failed worktree or
branch inventory becomes `UNKNOWN`; partial output is discarded and the repository is not counted as
successfully audited.

## What this does not answer

"Can I delete this repository safely?" is deletion triage, an inventory of dirty files, stashes,
and unpushed branches, and belongs to `/repo-hygiene:clean` (its scan/stash/git tiers), which owns
per-repository disposability analysis. This audit is a read-only cross-repository evidence REPORT;
it names candidates and hands off. Linked unlocked worktrees are named in `worktree-status-handoff`
for `/source-control:worktree status` stranded-work classification. This audit does not emit a
`git status`-based reclaimability substitute.

## Requirements

- Git with `git worktree list --porcelain -z` and `git rev-parse --path-format=absolute` support.
- Bash (Claude Code's Bash tool; Git Bash is the supported Windows path).
- Optional: authenticated GitHub CLI (`gh`) for bounded merged-PR and moved/renamed-repository
  evidence. GNU `timeout` (GNU/Linux and Git Bash) or `gtimeout` (GNU coreutils on macOS) is preferred;
  the collector provides its own finite Bash watchdog when neither compatible command is available.

## Security review

The plugin-acceptance review is recorded in
[`reference/security-review.md`](skills/audit/reference/security-review.md). The audit script uses no
`eval`, never sources consumer configuration, never follows filesystem links during discovery, sends
no local content to GitHub, and exposes only an explicit allowlist of read-only Git/GitHub command
shapes.

The current official documentation and the decisions each source supports are recorded in
[`reference/official-sources.md`](skills/audit/reference/official-sources.md).

## License

MIT (SPDX-License-Identifier: MIT). See the repository root LICENSE.
