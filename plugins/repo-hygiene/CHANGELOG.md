# Changelog

All notable changes to the `repo-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.0]

### Added

- **Fleet (batch) mode for the selective `caches` / `build` / `git` / `all`
  tiers.** A new `clean-batch.sh --tier <caches|build|git|all>` orchestrator runs
  the single-repo tiers across a set of repositories behind ONE confirmation gate,
  the way `tree-batch` already does for the destructive `tree` tier. It runs no
  removal itself — each per-repo action delegates to the unchanged single-repo
  child (`clean-caches.sh`, `clean-build.sh`, `git-prune.sh`), so every child gate
  (protection classes, submodule/reparse guards, the dry-run manifest + re-stat
  staleness guard) is reused verbatim. New action spellings `caches-batch` /
  `build-batch` / `git-batch` / `all-batch` (plus `*-fleet` aliases) resolve to it.
  (#994)
- **The batch plan is the gated set.** `--dry-run` writes a plan enumerating
  exactly the repos and shared object stores to act on (plus a per-repo child
  manifest for `caches`/`build`), prints `BatchPlan: <path>` and an aggregate
  `Summary: repos=N planned=P bytes=K`. `--apply --batch-plan <plan>` acts on that
  plan ONLY and is a usage error without it — so a live fleet that races the sweep
  is tolerated exactly: a repo that vanished after the dry-run applies idempotently
  (its manifest paths are already gone), a repo that appeared is not in the plan and
  is never touched. (#994)
- **Central path normalization + shared-object-store dedup in the batch layer**
  (`lib/batch-common.sh`). `ghq list -p` backslash paths are normalized once to the
  git-friendly `D:/repos/...` forward-slash form (backslashes break `xargs` and
  `[[ -d ]]`; `git check-ignore` rejects MSYS `/d/…` forms). The `git` tier groups
  repos by unique `git rev-parse --git-common-dir` and prunes each shared object
  store once, not once per linked worktree. (#994)

## [0.5.0]

### Fixed

- **Selective `caches`/`build` tiers now run a single pruned walk per tier instead
  of ~10 unpruned full-tree `find` walks.** The old `! -path` exclusions filtered
  output but did not `-prune`, so every per-pattern walk still descended `.git/`,
  `node_modules/`, and `.venv/`. Enumeration now prunes those three trees once and
  `-print`s all directory-name and file-glob matches in one walk, then applies
  per-path protection on the result list. Measured on a large .NET + node repo
  (Windows/NTFS): one pruned walk incl. `du` sizing ~17s vs a 10-walk unpruned
  dry-run that exceeded 10 min (killed). (#993)

### Added

- **Dry-run writes a manifest and states reclaimable space; `--apply` consumes it
  instead of re-walking.** The dry-run emits a session-scoped manifest
  (`<class>\t<bytes>\t<relpath>` per eligible target), prints its path
  (`Manifest: <path>`), and a `Summary: planned=N bytes=K` total so the
  confirmation gate can state reclaimable bytes. `--apply --manifest <path>`
  removes the manifest's entries with a re-stat + re-classify staleness guard (no
  second walk); a killed apply resumes by re-running the same command
  (already-gone entries are idempotent no-ops). `--apply` without a manifest
  builds one then applies it, preserving the standalone CLI contract. With
  `--include-caches` the caches tier folds into the same manifest — one walk per
  tier, no subprocess. (#995)
- **Apply ends with a machine-parseable summary and fails closed.** Each `--apply`
  run prints `Summary: removed=N failed=M bytes=K` (bytes actually reclaimed) and
  exits non-zero when any removal fails, so a fleet sweep no longer requires
  grepping every per-repo log to confirm success. (#1002)

### Removed

- **The `dotnet clean` build-system driver.** `clean-build.sh` no longer runs
  `dotnet clean <solution>` before removing `bin/`/`obj/`. The universal artifact
  removal already deletes everything the driver would, so running it first was
  pure overhead — a full MSBuild evaluation (minutes on a large solution) that
  also re-created `obj/` evaluation artifacts. One walk + `rm` is strictly faster
  and equally complete. Removes the `Planned: dotnet clean …` (dry-run) and
  `DRIVER_FAILED:` (apply) output markers. (#999)

## [0.4.6]

### Fixed

- **Destructive-guard hook now launches on Windows — was silently fail-open.** The
  exec-form hook (`command: "bash"` + `args`) resolves `bash` via PATH, which on
  Windows finds the WSL relay (`System32\bash.exe`) and fails to launch; Claude Code
  treats a failed hook launch as non-blocking, so the guard enforced nothing (48
  errors in one field session). The hook now uses shell form with `shell: bash`,
  which Claude Code runs via Git Bash on Windows — the guard launches wherever the
  skill itself can run.
- **Missing jq now degrades fail-closed instead of fail-open.** Without jq the guard
  previously announced itself inactive and allowed everything. It now matches the
  destructive patterns against the raw hook payload and blocks outright (the
  `CLEAN_GUARD_ACK` acknowledgement is unverifiable without jq); benign commands
  still pass. Install jq to restore the confirmation-gated flow.

## [0.4.5]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.4]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.3]

### Fixed

- **`tree-batch` — `--repo` now consumes every consecutive path, so the documented
  shell-glob form works.** `--repo ~/repos/*` reaches the script as one `--repo`
  flag followed by N positional paths (the shell expands the glob before exec), but
  the arg-parsing arm consumed only the first: the second expanded path hit the
  unknown-argument default and the batch exited 2. The documented glob usage
  therefore always failed whenever the glob matched more than one directory. The
  `--repo` arm now greedily ingests every consecutive non-flag path, halting at the
  next `-`-prefixed flag or end of args, so the advertised `--repo ~/repos/*` form
  is ingested whole. Repeated `--repo` and `--repos-from -` are unchanged. A bare
  `--repo` with no following path (end of args or immediately followed by a flag)
  now fails loud with a usage error instead of silently absorbing the next flag as a
  directory. (#650)

## [0.4.2]

### Fixed

- **`git-tree-reset` context doc — surfaces the `reset --hard` non-atomicity
  caveat on the exit-5 gate.** The exit-5 bullet in
  `skills/clean/context/git-tree-reset.md` accurately described the gating
  contract (a failed `reset --hard` skips `clean` and the restore guard, so the
  tree is never left cleaned-but-not-reset) but omitted that `reset --hard` is
  not atomic and may have partially modified tracked files before it failed —
  a caveat the runtime exit-5 stderr message already surfaces. The bullet now
  carries that parenthetical, so the doc is consistent with the script's stderr
  output. (#485)

## [0.4.1]

### Fixed

- **`git-tree-reset` — exit-7 clean-failure path now emits the restore-guard
  warning identically to the success path.** When `git clean -fdx` fails for a
  non-locked-file cause (exit 7) after the restore guard recovered one or more
  tracked files deleted via reparse-point traversal (`RestoredTracked: N`, N>0),
  the path now prints the same `WARNING: restored N tracked file(s)` message the
  success path already emits under that condition. Previously the warning was
  emitted only on the success path, so an operator hitting the failure path saw
  the machine-readable `RestoredTracked: N` line but not the human-visible signal
  that data-loss recovery fired — parity between both paths for this specific
  signal. (#605)

## [0.4.0]

### Added

- **`tree-batch` — multi-repo working-tree reset with a skip-list and a dirty guard.**
  A new `clean` action that runs the `tree` tier across a set of repositories
  (`ghq list` output via `--repos-from -`, a shell glob, or explicit `--repo`
  flags) behind a single dry-run -> confirm -> apply gate, then reports a per-repo
  outcome summary (`would-reset` / `done` / `skipped` / `blocked` / `failed`). It
  is a thin orchestrator: every per-repo reset delegates to the unchanged
  `git-tree-reset.sh`, so all single-repo safety gates are reused verbatim and the
  single-repo behavior is untouched.

  Closes the gap that caused an unrecoverable data loss when an operator
  hand-rolled a `ghq list` reset loop. Two defects are fixed as first-class
  behavior: (1) **separator-agnostic skip-matching** — a skip entry and the
  enumerated repo path are each normalized to a canonical separator-agnostic key
  (`clean_path_key`) before comparison, so a Windows `\`-path skip entry reliably
  matches a repo whose path git enumerated with `/` (the exact match that silently
  failed and reset a repo that should have been skipped); a skip entry matching no
  repo is surfaced as `UnmatchedSkip:`, never silently ignored. (2) **Dirty-by-
  default guard** — a repo with uncommitted/untracked changes or unpushed commits
  is skipped with a reported reason; `--include-dirty` opts in and is gated with
  its own explicit confirmation, like `--include-secrets`.

## [0.3.3]

### Fixed

- **`git-tree-reset.sh` — `AppliedClean` no longer claims success when `git clean` failed.**
  On the `--apply` path the script captured `git clean -fdx` stderr but never checked its
  exit status, then printed `AppliedClean: git clean -fdx …` unconditionally — so a clean
  that errored still reported success, misleading any operator or automation keying off that
  line to conclude the tree reached a known-good state. The clean exit code is now inspected:
  a non-zero exit whose cause is NOT locked/in-use files (the expected non-fatal case, already
  reported via `Unremovable:`) is a genuine failure that prints an explicit `FAILED:` line and
  `AppliedClean: failed` instead of a success line, and exits 7. The `AppliedReset:` success
  line is now emitted as soon as the reset genuinely succeeds — before `clean` — so a
  subsequent clean failure still surfaces the truthful reset outcome. The reparse-point restore
  guard runs on the failure path too, so tracked files a partially-run clean may have deleted
  are still recovered.

## [0.3.2]

### Fixed

- **`git-tree-reset.sh` — unresolvable upstream now gated before any destructive op.**
  When a branch's upstream is configured (`branch.<name>.remote` + `.merge`) but its
  remote-tracking ref is absent — e.g. a feature branch whose squash-merged PR left the
  remote branch deleted and pruned — `git rev-parse --abbrev-ref '@{u}'` prints the literal
  token `@{u}` rather than a ref name, and the trailing pipe masked git's non-zero exit, so
  the non-empty guard passed and `UPSTREAM=@{u}`. On `--apply` this reached `git reset --hard
  @{u}` → `fatal: ambiguous argument '@{u}'`, and (before the reset-success gate) `git clean
  -fdx` still ran — a partial destructive op (tree cleaned but not reset). The script now
  verifies `@{u}` resolves to a real ref (a local-only upstream, `branch.remote="."`, still
  resolves and passes) and otherwise skips the repo with `Blocked: upstream-unresolved
  (<remote>/<branch>)` and `PlannedReset`/`PlannedClean: none` before any `reset`/`clean`,
  exiting 6. A literal `@{u}` can never reach `reset --hard`.

## [0.3.1]

### Fixed

- **`git-tree-reset.sh` — `clean` now gated on a successful `reset --hard`.** The
  `--apply` path runs under `set -uo pipefail` (no `-e`) and never checked the
  `git reset --hard` exit status before running `git clean -fdx`, so a failed reset
  fell through to the destructive clean — leaving the tree cleaned but not reset (a
  partial destructive op). A non-zero reset now aborts the apply before `clean` and
  the reparse-point restore guard ever run, prints an explicit failure line, emits
  honest `AppliedReset: failed` / `AppliedClean: none` (never a success line for a
  command that failed), and exits 5.

## [0.3.0]

### Added

- **`remove-path.sh` — guarded orphaned-path removal.** A new `clean` skill action that
  removes a whole orphaned clone or leftover directory under the ghq root (`--root`
  overrides) — the whole-directory deletion the selective tiers never perform (e.g. a local
  clone whose upstream repository was deleted). Defaults to `--dry-run`; it is not composed
  into any tier and runs only on explicit request. Guards resolve both sides physically
  before a strict-containment check (a symlinked/junction ancestor cannot slip a target
  outside the root) and require the target to share the root's filesystem device (an
  ancestor bind mount to another filesystem cannot escape it either; a same-device bind
  mount is the documented residual of this path-based containment model), and refuse the
  containment root itself, symlink/reparse-point targets, linked worktrees, and any plain
  directory still holding nested git repos — a normal clone, a submodule/linked worktree, or
  a bare mirror. A repo (or bare repo) is blocked on uncommitted changes, stash entries,
  registered worktrees, ignored secret-class files (`--include-secrets` to override), or
  unpushed work — unpushed branches or local-only tags (`--allow-unpushed` to override); a
  plain directory is scanned for the same secret class, and any git state that cannot be
  inspected (working tree, stash, or worktree list) fails closed. Any target holding ignored
  skill-owned `data/` (irreplaceable user synthesis) is refused with no override, matching the
  clean skill's always-preserve policy. Removal itself runs `rm -rf` bounded to one filesystem
  where supported.

## [0.2.1]

### Fixed

- The `clean` skill's PreToolUse destructive-guard hook now uses the
  interpreter-named exec form (`command: "bash"`,
  `args: [".../destructive-guard.sh"]`) instead of naming the bare `.sh` as
  the command — the doctrine-prescribed Windows-safe spawn shape
  (cross-platform declaration wave).

## [0.2.0]

### Changed

- **Destructive-guard kill switch migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling): the `clean_destructive_guard_enabled` boolean (default
  `true`) now gates the session-scoped destructive guard, read through the native
  `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` hook-process mirror. Configure
  with `/plugin configure repo-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_CLEAN_DESTRUCTIVE_GUARD_ENABLED` environment variable is retired
  and no longer read. Zero-config behavior is unchanged (guard active while the clean skill
  is active).
