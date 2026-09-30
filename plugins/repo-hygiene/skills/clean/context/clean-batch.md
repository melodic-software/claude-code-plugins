# The batch (fleet) selective tiers: `scan-batch` / `caches-batch` / `build-batch` / `git-batch` / `all-batch`

Full detail for the fleet form of the selective tiers. SKILL.md §8 carries the
headline; this file carries the gate, the script contract, and examples. The
single-repo tiers ([action-router.md](action-router.md)) are unchanged;
`clean-batch.sh` is an additive orchestrator over them, the selective-tier
sibling of `tree-batch` ([git-tree-reset-batch.md](git-tree-reset-batch.md)).

## Why this exists

Batch mode lives in the skill as a sanctioned script. Without a fleet path, a
session cleaning a large `ghq` fleet from a non-repo cwd has to hand-roll batch
dry-run/apply scripts around the per-repo tiers, and a hand-rolled bulk `rm`
pipeline is blocked by the auto-mode classifier even after explicit confirmation,
while the sanctioned skill-script apply passes.

## Scope

**In:** run the single-repo `caches` / `build` / `git` tiers (and `all` = build +
git) across a set of repositories behind one confirmation gate, then report a
per-repo outcome summary. The read-only `scan` tier runs across the same set with no gate.

**Out:**

- **`tree`**: the destructive tier has its own batch form (`tree-batch`) with a
  dirty guard; it is never folded into `all` and not handled here.
- **Branch deletion**: interactive per-branch deletion cannot sit behind one
  fleet-wide gate. Batch `git` is prune / gc / remote-prune only. The read-only
  audits do take this repo selection: `git-branch-audit.sh` and
  `git-stash-audit.sh` accept `--repo`, `--repos-from`, `--skip`, `--skip-from`
  and print a `Repo: <path>` block per repo; delete from inside the audited repo.
  A branch or worktree audit across many repositories, including one outside the ghq
  root, is `/repo-fleet-hygiene:audit` (`--root`, `--repo`), which hands per-repo
  cleanup back here.
- The actual removal / prune: delegated to the unchanged single-repo child. The
  batch layer runs no destructive command itself.

## Script

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier <scan|caches|build|git|all> \
  [--dry-run|--apply] \
  [--repo DIR]... [--repos-from FILE|-]... [--fleet] \
  [--skip ENTRY]... [--skip-from FILE]... \
  [--batch-plan FILE]
```

Default: `--dry-run`. `--batch-plan FILE` is also accepted with `--dry-run`, to write the
plan to a stable path instead of the default state directory (below). Output labels and full flag help: script `--help`.

### Tiers

| Tier | Per repo | Notes |
| --- | --- | --- |
| `scan` | `scan.sh` | read-only inventory; no plan, no `--apply` (below) |
| `caches` | `clean-caches.sh` | tool/linter caches |
| `build` | `clean-build.sh --include-caches` | build output + caches (single-repo `build` includes caches) |
| `git` | `git-prune.sh`, once per unique shared object store | prune / gc / remote-prune; no branch audit |
| `all` | build + git | mirrors the single-repo `all` tier (no branch audit, no tree) |

### Repo sources

A `ghq list`, a shell glob, and an explicit list all reduce to a path list:

| Source | How |
| --- | --- |
| explicit list | `--repo DIR` (repeatable) |
| shell glob | the shell expands it into repeated `--repo DIR` |
| `ghq list` | `ghq list -p \| … --repos-from -` (or `--repos-from FILE`) |
| fleet discovery | `--fleet`: every `ghq list -p` repo when `ghq` resolves, plus `chezmoi source-path` when `chezmoi` resolves and that path is in a git repo. A missing tool adds nothing; no repos at all is a usage error. `--fleet` also dedupes clones (below). |

Backslash paths from `ghq list -p` (`<drive>:\repos\...`) are normalized once to the
git-friendly `<drive>:/repos/...` form; inputs are resolved to their canonical toplevel
(`git rev-parse --show-toplevel`) and deduped, so the same repo named two ways is
processed once. A non-directory or non-git input is reported as a `blocked`
outcome, never silently dropped.

`--fleet` dedupes clones by origin remote across the whole set; `--repo` and
`--repos-from` alone never do. Two clones of one remote each hold their own working-tree
caches, build output and object store, so a repo you name is always planned. To clean every
clone, leave `--fleet` off. With `--fleet`, the URL is compared with the scheme, `user@` and a
trailing `.git` or `/` removed, the host lowercased (on `github.com` the owner and repo too),
and scp form (`git@host:o/r`) read as `host/o/r`. The first clone that is not skip-listed
stays; each other is one `skipped duplicate of <path>` record, counted in `skipped=` and not
in `repos=`. A skip-listed clone is neither kept nor a duplicate, so skipping one clone never
drops its sibling. Linked worktrees of one repository are not clones and are left to the git
tier's shared-object-store dedup. A repo with no `origin` is never deduped.

### Skip list (separator-agnostic)

`--skip ENTRY` (repeatable) / `--skip-from FILE`, reusing the exact matcher
`tree-batch` uses: an entry may be an absolute path, an `owner/repo` suffix, or a
bare `repo`; matching is separator-agnostic and anchored on segment boundaries
(`repo` never matches `other-repo`). A skip entry that matches **no** enumerated
repo is reported as `UnmatchedSkip:`.

### Shared object store dedup (the `git` tier)

Linked worktrees share the main clone's objects, so `git gc` / prune must run once
per unique `git rev-parse --git-common-dir`, not once per worktree. The `git` and
`all` tiers group repos by common dir and record each store once (as a `GITDIR`
plan line with a representative worktree to `cd` into); `gitdirs=N` in the summary
reports the deduped count. The dry-run counts each store once, and only what the apply
ops act on, into `planned=` and `bytes=`: the worktrees `git worktree prune --dry-run`
would remove, plus the loose objects and garbage of `git count-objects -v` when
`git gc --auto` would run, meaning loose objects above `gc.auto` or packs
above `gc.autoPackLimit`, neither check running when `gc.auto` is 0 or less.
Below those limits `gc --auto` removes nothing, so a store with nothing else to prune
counts 0 items and 0 bytes yet stays `would-clean`, because apply still runs
`git remote prune origin`. Git samples one fan-out directory for its own trigger, so
the trigger here is approximate, and the bytes above it are an upper bound: `gc` packs
reachable loose objects instead of deleting them. Remote-prune candidates are not
counted because finding them needs a network call. The git and all tiers end the summary with
`git_bytes=B`; `all` also adds `caches_bytes=C build_bytes=D`, split by manifest class.
These fields come after the existing ones.

**Known limitation.** The plan stores only the first-seen worktree as each store's
representative. If that specific worktree vanishes before apply while a live
sibling still shares the store, the prune is reported `skipped`, not run. It is
deferred, not lost: `git` prune/gc is non-destructive and idempotent, and a fresh
dry-run → apply over the live siblings picks a new representative.

### The batch plan IS the gated set

`--dry-run` writes a plan file enumerating exactly the repos and shared object
stores to act on, plus a per-repo child manifest for `caches`/`build`, and prints
`BatchPlan: <path>`. `--apply --batch-plan <path>` acts on **that plan only** and
errors without it (the fleet gate is mandatory). This is the fleet-level analogue
of the child's per-repo manifest staleness guard, and it is what makes a live
fleet safe to sweep: a repo that vanished after the dry-run applies idempotently
(its manifest paths are already gone); a repo that appeared is not in the plan, so
it is never touched. Do not re-enumerate at apply. Pass the plan back.

Default location: a fresh `clean-batch.XXXXXX` directory under
`${XDG_STATE_HOME:-$HOME/.local/state}/repo-hygiene/`, wherever the command runs. It is
never under `/tmp`, so it also works where the guardrails `block-windows-drive-tmp` hook
rejects a temp-dir path (Windows), and never inside a repo: `.work/` is ignored only by
some repos' own convention, so a plan there would leave the working tree dirty. An apply
that finishes with `failed=0` removes the plan, its manifests and that directory. A
dry-run that is never applied, and an apply that fails, leave the directory; `BatchPlan:`
names it. `--batch-plan FILE` overrides the location and is never removed: pass a path
outside `/tmp` there too.

`RUNTIME_PROCS` and `RECENT_BUILD` are scoped to the batch repositories and `IDE_OPEN` is
machine-wide. Apply does not re-run preflight, so the preflight facts (`RUNTIME_PROCS`,
`IDE_OPEN`, `RECENT_BUILD`) are as of the dry-run; after a long gap run
`preflight.sh` again before confirming. `planned=` bytes can exceed `removed=`
bytes when entries vanished between the runs; both numbers are correct.

Apply also validates the plan against the requested `--tier` before touching disk:
the plan must have been built for the same tier. A plan carrying a record the tier
does not authorize is refused atomically (usage error, nothing removed, no apply
banner), so the `--tier` flag can never under-report the scope of what a swapped or
stale plan removes. Those records are a `build` REPO record (which folds caches)
under `--tier caches`, a `caches` record under `build`, and a `GITDIR` record under
a non-git tier.

The check runs in both directions. `all` authorizes both record kinds, so a
narrower plan would clear every per-record test and then run only part of the tier.
A `build` plan (no `GITDIR` records) applied with `--tier all` would skip every
prune, and a `git` plan (no `REPO` records) would skip every build removal. A non-empty
plan applied with `--tier all` must therefore carry both kinds, or it is refused
the same way. An empty plan plans nothing for either kind and stays a no-op.

Only a structurally well-formed record satisfies that both-kinds requirement. A
`GITDIR` line naming no representative worktree, or a `REPO` line naming no
manifest, names no target and so cannot stand in for the tier half it belongs to.
A malformed record is a different error class from a wrong-tier plan: the plan is
not refused wholesale, but the record fails closed per-record at apply (structural
corruption, exit 1, counted in `failed=` and never in `gitdirs=`) rather than being
reported as a store that vanished after the dry-run.

### Per-repo outcome

Each repo emits `Repo:` / `Outcome:` / `Reason:`. Outcomes: `would-clean`
(dry-run) / `nothing-to-do` (dry-run: a repo with no paths to
remove and no new shared object store; its plan record still applies as a no-op) / `scanned` (scan tier) / `cleaned` (apply, selective tiers) / `pruned` (apply, git tier) /
`skipped` (skip-list, or vanished after the dry-run) / `blocked` (non-git input) /
`failed` (a child `rm` failed). A dry-run also prints a `Repo | Outcome | Paths | Bytes` table, one row per repo
(skipped and blocked repos show 0 and 0), before `BatchPlan:`. A closing `Summary:` totals the batch and exits
non-zero when any repo failed. After apply, report the `failed`, `blocked`, and
`skipped` repos with their reasons before the totals: those need the user.

### The scan tier is read-only

`--tier scan` runs the unchanged `scan.sh` in each selected repo, with the same repo
sources and skip list as the other tiers. It writes no plan and runs no preflight, and
`--apply` or `--batch-plan` with it is a usage error (exit 2), so there is no gate to
pass. Each repo emits `Outcome: scanned` with its path count and reclaimable size; a repo
whose `scan.sh` prints no `Total reclaimable` is `blocked`, never counted as 0. The closing
`Summary: repos=N planned=0 bytes=K skipped=S blocked=B` sums `Total reclaimable` over the
scanned repos. Linked worktrees are scanned as separate repos (their artifacts are separate
paths). For one repo's per-path inventory, run `scan.sh` inside it.

## Gates

- **Single batch-wide gate:** run `--dry-run` once, show the whole-batch plan (the
  per-repo outcomes + `Summary` + any `UnmatchedSkip`), [confirmation gate](../SKILL.md#confirmation-gate) once,
  surfacing the `bytes` reclaimable total, then `--apply --batch-plan <path>` once.
  One confirmation covers the batch; do not gate per repo.
- **Autonomous sessions** (`CLAUDE_CODE_REMOTE`, `/loop`, `/schedule`): `--apply`
  aborts, same rule as the single-repo selective tiers.
- The wrapper runs each child as a subprocess, so the session destructive guard
  sees only `bash clean-batch.sh`, not an inline `rm -rf`. Invoke via the
  wrapper, and per the selective-tier convention prefix the apply with
  `CLEAN_GUARD_ACK=1` after the gate passes.

## Examples

Dry-run a caches sweep of the whole `ghq` tree, skipping one repo, then apply the
gated plan after confirming:

```bash
ghq list -p | bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier caches --repos-from - --skip melodic-software/standards
# → BatchPlan: <state-dir>/clean-batch.…/plan  — confirm, then:
CLEAN_GUARD_ACK=1 bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier caches --apply --batch-plan <state-dir>/clean-batch.…/plan
```

Dry-run a git prune across an explicit set including worktrees (each shared store
pruned once):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier git --repo ~/repos/a --repo ~/repos/a-worktree --repo ~/repos/b
```
