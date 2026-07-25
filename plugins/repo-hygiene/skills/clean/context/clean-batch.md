# The batch (fleet) selective tiers — `caches-batch` / `build-batch` / `git-batch` / `all-batch`

Full detail for the fleet form of the selective tiers. SKILL.md §8 carries the
headline; this file carries the gate, the script contract, and examples. The
single-repo tiers ([action-router.md](action-router.md)) are unchanged;
`clean-batch.sh` is an additive orchestrator over them, the selective-tier
sibling of `tree-batch` ([git-tree-reset-batch.md](git-tree-reset-batch.md)).

## Why this exists

Invoking the clean skill over an 82-repo `ghq` fleet from a non-repo cwd yielded
no fleet path — the session had to hand-roll batch dry-run/apply scripts around
the per-repo tiers, and the auto-mode classifier then blocked the hand-rolled bulk
`rm` pipeline even after explicit confirmation while the sanctioned skill-script
apply passed. Batch mode must live IN the skill as a sanctioned script. This is it.

## Scope

**In:** run the single-repo `caches` / `build` / `git` tiers (and `all` = build +
git) across a set of repositories behind one confirmation gate, then report a
per-repo outcome summary.

**Out:**

- **`tree`** — the destructive tier has its own batch form (`tree-batch`) with a
  dirty guard; it is never folded into `all` and not handled here.
- **Branch audit / deletion** — the single-repo `git` tier also audits branches
  for interactive per-branch deletion, which cannot sit behind one fleet-wide
  gate. Batch `git` is prune / gc / remote-prune only; run branch cleanup per repo.
- The actual removal / prune — delegated to the unchanged single-repo child. The
  batch layer runs no destructive command itself.

## Script

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier <caches|build|git|all> \
  [--dry-run|--apply] \
  [--repo DIR]... [--repos-from FILE|-]... \
  [--skip ENTRY]... [--skip-from FILE]... \
  [--batch-plan FILE]
```

Default: `--dry-run`. Output labels and full flag help: script `--help`.

### Tiers

| Tier | Per repo | Notes |
| --- | --- | --- |
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

Backslash paths from `ghq list -p` (`D:\repos\...`) are normalized once to the
git-friendly `D:/repos/...` form; inputs are resolved to their canonical toplevel
(`git rev-parse --show-toplevel`) and deduped, so the same repo named two ways is
processed once. A non-directory or non-git input is reported as a `blocked`
outcome, never silently dropped.

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
reports the deduped count.

**Known limitation.** The plan stores only the first-seen worktree as each store's
representative. If that specific worktree vanishes before apply while a live
sibling still shares the store, the prune is reported `skipped`, not run — it is
deferred, not lost: `git` prune/gc is non-destructive and idempotent, and a fresh
dry-run → apply over the live siblings picks a new representative. Widening the
plan to carry fallback candidates is a possible future refinement.

### The batch plan IS the gated set

`--dry-run` writes a plan file enumerating exactly the repos and shared object
stores to act on, plus a per-repo child manifest for `caches`/`build`, and prints
`BatchPlan: <path>`. `--apply --batch-plan <path>` acts on **that plan only** and
errors without it (the fleet gate is mandatory). This is the fleet-level analogue
of the child's per-repo manifest staleness guard, and it is what makes a live
fleet safe to sweep: a repo that vanished after the dry-run applies idempotently
(its manifest paths are already gone); a repo that appeared is not in the plan, so
it is never touched. Do not re-enumerate at apply — pass the plan back.

Apply also validates the plan against the requested `--tier` before touching disk:
the plan must have been built for the same tier. A plan whose records the tier does
not authorize — a `build` REPO record (which folds caches) under `--tier caches`, a
`caches` record under `build`, or a `GITDIR` record under a non-git tier — is
refused atomically (usage error, nothing removed, no apply banner) so the `--tier`
flag can never under-report the scope of what a swapped or stale plan removes.

The check runs in both directions. `all` authorizes both record kinds, so a
narrower plan would clear every per-record test and then run only part of the tier
— a `build` plan (no `GITDIR` records) applied with `--tier all` would skip every
prune, a `git` plan (no `REPO` records) would skip every build removal. A non-empty
plan applied with `--tier all` must therefore carry both kinds, or it is refused
the same way. An empty plan plans nothing for either kind and stays a no-op.

### Per-repo outcome

Each repo emits `Repo:` / `Outcome:` / `Reason:`. Outcomes: `would-clean`
(dry-run) / `cleaned` (apply, selective tiers) / `pruned` (apply, git tier) /
`skipped` (skip-list, or vanished after the dry-run) / `blocked` (non-git input) /
`failed` (a child `rm` failed). A closing `Summary:` totals the batch and exits
non-zero when any repo failed.

## Gates

- **Single batch-wide gate:** run `--dry-run` once, show the whole-batch plan (the
  per-repo outcomes + `Summary` + any `UnmatchedSkip`), `AskUserQuestion` once —
  surface the `bytes` reclaimable total — then `--apply --batch-plan <path>` once.
  One confirmation covers the batch; do not gate per repo.
- **Autonomous sessions** (`CLAUDE_CODE_REMOTE`, `/loop`, `/schedule`): `--apply`
  aborts, same rule as the single-repo selective tiers.
- The wrapper runs each child as a subprocess, so the session destructive guard
  sees only `bash clean-batch.sh`, not an inline `rm -rf` — invoke via the
  wrapper, and per the selective-tier convention prefix the apply with
  `CLEAN_GUARD_ACK=1` after the gate passes.

## Examples

Dry-run a caches sweep of the whole `ghq` tree, skipping one repo, then apply the
gated plan after confirming:

```bash
ghq list -p | bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier caches --repos-from - --skip melodic-software/standards
# → BatchPlan: /tmp/…/plan  — confirm, then:
CLEAN_GUARD_ACK=1 bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier caches --apply --batch-plan /tmp/…/plan
```

Dry-run a git prune across an explicit set including worktrees (each shared store
pruned once):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/clean-batch.sh \
  --tier git --repo ~/repos/a --repo ~/repos/a-worktree --repo ~/repos/b
```
