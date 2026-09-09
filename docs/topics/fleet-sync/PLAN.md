# fleet-sync

## Brief

### TLDR

- New `repo-fleet-hygiene:sync` skill: for every canonical repo checkout in scope, switch to the default branch and fast-forward pull; park divergent work in a linked worktree instead of losing it.
- Zero-argument invocation infers scope from a six-rung ladder (explicit args, fleet conf, conversation-named paths, ghq if present, cwd context, else a transparent "nothing resolved" exit). The resolver is a shared plugin script that `audit` adopts as its no-scope fallback.
- Parking reuses `source-control`'s `worktree-create.sh` via a new existing-branch mode, so naming, root resolution, containment guard, `.worktreeinclude` copy, and lock claim are all inherited.
- Verb contract: bare invocation is a dry-run plan; mutation only with `--apply` after one confirmation gate. Non-fast-forward, dubious ownership, and partial stash apply are skip-and-report, never merge, rebase, reset, or config writes.
- Follow-up issue for `repo-hygiene:clean tree-batch` to gain the same zero-argument scope inference; not in this change.

### Goal

An operator on any machine can run one command from anywhere and have every canonical repository they own moved to its current default branch and fast-forwarded, with a report naming what moved, what was parked where, and what was skipped and why. Nothing uncommitted or unpushed is ever lost: work that would block the switch is moved into a linked worktree under the repository's configured worktree root and left exactly as it was.

### Constraints

- Lives in `plugins/repo-fleet-hygiene/skills/sync/`, sibling to `audit` and `apply`; `audit` stays read-only and its plan JSON schema is untouched (`apply-plan.sh` exits 2 on unknown operations, so sync never rides the plan).
- No hardcoded tool or layout: ghq, fleet conf, and cwd context are all presence-gated per `docs/PLUGIN-PHILOSOPHY.md` "Two-lane convention posture"; the skill works with none of them configured.
- Plugins stay horizontally decoupled: `repo-hygiene` does not call `repo-fleet-hygiene`'s resolver; the `source-control` change is confined to a new flag on `worktree-create.sh`.
- Every git invocation the script emits must stay outside the guardrails block list (`reset --hard`, `clean -f*`, `checkout .`, `restore .`, `checkout -f`, `switch -f`, `--discard-changes`, force push). Allowed and used: `switch`, `pull --ff-only`, `fetch`, `ls-remote --symref`, `worktree add`, `stash push -u`/`apply`/`drop`, `status --porcelain`, `rev-list --count`.
- Stash handling: `stash push -u -m <unique marker>`, resolve the entry by marker to its SHA, `stash apply <sha>` in the park, then explicit `drop` by re-found ref; never bare `stash`/`pop` (the stack is repository-wide and shared with other sessions).
- Skill body follows `.claude/rules/skill-bodies-state-current-rules.md` (state rule and reason, no incident or PR citations, `## Next` section); frontmatter carries a paired `${CLAUDE_SKILL_DIR}` `allowed-tools` grant; `allowed-tools-pairing.test.sh` `SKILLS=` array gains `sync`.
- Tests are co-located plain-bash `<stem>.test.sh` selected by `scripts/affected-tests.sh`; every changed file must map to a suite. PR opens as a draft. Conventional Commits.
- Cross-platform: Bash script must run under Git Bash on Windows (paths via the repo's windows-path-emit convention) and on Linux CI; the Windows CI lane is informational.

### Acceptance criteria

- Bare `/repo-fleet-hygiene:sync` from inside a repo under a multi-repo parent, with no fleet conf and no ghq, resolves that parent as a root, prints a dry-run plan listing every repo with its source rung and intended action, and mutates nothing.
- With ghq on PATH and no other scope, every `ghq root --all` entry is used as a root; with explicit args or a fleet conf present, rungs 4 and 5 are not consulted.
- With no scope resolvable at any rung, the run prints what each rung probed and the remedies (pass a directory, run `repo-fleet-hygiene:setup`, install ghq) and exits 3 without touching any repository.
- `audit-fleet.sh` invoked with no scope and no config falls back to the shared resolver instead of failing with "no scope resolved"; its existing tests still pass and its `allowed-tools` grant is unchanged.
- `--apply` on a repo that is on the default branch, clean, and behind origin results in a fast-forward; `git rev-parse HEAD` equals `origin/<default>` afterwards.
- `--apply` on a repo whose canonical checkout is on a non-default branch with uncommitted changes leaves the canonical on the default branch, fast-forwarded, and a linked worktree at `<worktree-root>/<owner>-<repo>-<slug>` checked out on that branch with the uncommitted changes (tracked and untracked) present and no stash entry left behind.
- `--apply` on a repo on the default branch with a dirty tree parks the changes on a new `park/<date>-<short-sha>` branch in a linked worktree, then fast-forwards the canonical.
- A non-default branch that is clean and fully pushed is switched to default with no worktree created; the local branch ref survives.
- `pull --ff-only` failing (exit 1 or 128), a dubious-ownership refusal, and a stash apply that returns non-zero each produce a skipped/failed line naming the repo, the git exit code, and the remedy; the stash entry is retained on apply failure; the run continues with the next repo and exits non-zero at the end.
- The default branch is taken from `git ls-remote --symref origin HEAD`; a repo whose local `origin/HEAD` points at a renamed-away branch still syncs to the remote's current default.
- `--repo`, `--root`, `--repos-from FILE|-`, `--skip`, `--skip-from`, `--dry-run` (default), `--apply` are accepted; duplicates across rungs are deduplicated by git common dir; linked worktrees given as targets are retargeted to their main worktree.
- `worktree-create.sh` gains an existing-branch mode that refuses when the branch is checked out elsewhere (git's own exit 128 surfaced, never `--force`) and otherwise behaves identically to the new-branch mode for root resolution, containment, `.worktreeinclude`, and lock; its existing tests pass and a new test covers the mode.
- `scripts/affected-tests.sh --run` passes for the change set on Linux; the skill passes `skill-quality:check`.

### Captured assumptions

- No minimum git version gate; `ls-remote --symref` predates every git in the fleet. Revisit if a fleet host reports a `ls-remote` that lacks `--symref`.
- Stash breadth is `-u` (untracked, not ignored); ignored files are rebuildable. Revisit if an operator reports losing gitignored local state they needed.
- Rung 5's ancestor probe uses "≤4 levels up, directory directly holding ≥2 repos". Revisit if a fleet layout nests roots deeper or keeps single-repo folders that should count.
- `safe.directory` is never written by sync; the remedy is printed. Revisit if the fleet standardises on a per-root `'<root>/*'` entry via setup.
- Acceptance-criteria coverage prompt was asked; unwanted-behaviour cases are covered above (ff-only failure, partial apply, dubious ownership); no additional state-driven case was requested.
- Research verification: git semantics were verified against git's own docs, source, and binary, then corroborated from a second pool for 16 of 18 load-bearing claims; the two uncorroborated (double-`--force` worktree nuance, Windows ownership carve-outs) are not used by the design.

### Out-of-scope

- Adding `canonical-not-on-default`, `dirty-canonical`, `ahead-or-diverged` findings to `audit-fleet.sh` (Q3); sync computes them itself.
- A `--reset-diverged` escape hatch that shells to `git-tree-reset.sh` (Q8 alternative).
- Zero-argument scope inference for `repo-hygiene:clean tree-batch` (Q13); filed as a follow-up issue.
- Riding the audit's plan JSON or extending `apply-plan.sh` (Q2).
- Any merge, rebase, or reset fallback when a fast-forward is not possible.

### Deferred questions

- Q6 — exact `park/<date>-<short-sha>` naming and whether the date is UTC; defer until implementation; **arbiter: /planning:plan**
- Q14 — the exact flag name and output line format for reporting each target's source rung; defer until implementation; **arbiter: /planning:plan**

## Plan
