---
description: "Repo hygiene action-router: scan (inventory), caches, build, git (prune/branch audit), stash (stash audit/triage), tree (destructive fresh-pull reset), tree-batch (multi-repo tree reset with skip-list + dirty guard), all, and fleet batch forms of the selective tiers (caches-batch / build-batch / git-batch / all-batch over many repos behind one gate). Bare invocation detects intent from conversation or shows a menu. Dry-run-first; destructive actions require explicit confirmation. Use when reclaiming disk space in a repo, clearing tool caches or build artifacts, pruning git metadata, auditing stale branches or stashes, or resetting a working tree to match origin, in one repository or across a fleet: 'clean', 'free up disk space', 'fresh pull', 'stale branches', 'repo hygiene'. Skip: removing git worktree directories (a worktree-management tool handles those)."
user-invocable: true
disable-model-invocation: false
argument-hint: "[scan|caches|build|git|stash|tree|all|<tier>-batch|aliases…]"
allowed-tools:
  # Scripts that delete nothing, one narrow rule each. The mutating scripts
  # (clean-caches / clean-build / git-prune / git-tree-reset[-batch] /
  # remove-path / clean-batch) are deliberately NOT pre-approved: withholding
  # the grant is what keeps them behind the permission flow, which together
  # with the dry-run-then-confirm contract below is where the gate actually is.
  # NOT a claim that withholding the grant is the whole gate. The PreToolUse
  # destructive guard matches destructive command SHAPES (`rm -rf`,
  # `git clean -f*`, `git reset --hard`, `git checkout --`,
  # `git stash drop`/`clear`, recursive `Remove-Item`, `git branch -D`/`-d`/
  # `--delete`, `git push --delete` and `git push origin :ref` (also `+:ref`)), and it also
  # matches these scripts when the command text contains `--apply`, plus
  # `git worktree remove` with a force flag. A dry-run of the same scripts, or
  # of a push, does not match. It does not match obfuscated spellings (eval,
  # `bash -c`, aliases). The guard is a best-effort net over command text, not
  # a security boundary.
  # git-branch-audit.sh writes one TipCapture file under the git common dir
  # (.git/repo-hygiene/branch-tips/) per run, and its landed-proof squash step
  # writes one unreferenced loose object per branch it reaches.
  - Bash(${CLAUDE_SKILL_DIR}/scripts/resolve-clean-action.sh:*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/scan.sh:*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/preflight.sh:*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/git-branch-audit.sh:*)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/git-stash-audit.sh:*)
hooks:
  PreToolUse:
    # Both shell tools. The guard's own patterns include a PowerShell spelling
    # (recursive `Remove-Item`), and a `Bash`-only matcher can never deliver a
    # PowerShell call to it, so on a host whose primary shell is PowerShell the
    # guard was simply absent. `Bash|PowerShell` is the spelling every other
    # guard in this marketplace registers with, and a PowerShell tool call
    # carries its command in the same `.tool_input.command` field Bash uses.
    - matcher: "Bash|PowerShell"
      hooks:
        # Exec form. `command` is `node`. exec-bash.mjs finds Git Bash and
        # never System32\bash.exe, then runs destructive-guard.sh.
        # Claim: exec form spawns `command` with `args` and no shell, and a
        # skill-frontmatter hook substitutes only ${CLAUDE_PLUGIN_ROOT}.
        # Basis: https://code.claude.com/docs/en/hooks "Exec form and shell form"
        # and "Command hook fields".
        # As of: 2026-09-28.
        # Recheck: that page stops ignoring `shell` when `args` is set, or a
        # skill hook gains another placeholder.
        - type: command
          command: node
          args: ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive-guard.sh"]
metadata:
  workflow-stage: anytime
  summary: Clean caches, build artifacts, stale branches, and stashes per repo
---

**Arguments.** `[scan|caches|build|git|stash|tree|all|<tier>-batch|aliases…]`. Bare → menu or auto-detect. The action list is [context/action-router.md](context/action-router.md) "Canonical actions".

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Uncommitted changes (empty = none), `git status --porcelain | head -5`
- Current branch, `git branch --show-current`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 5 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the `source-control` plugin's
[worktree/reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Purpose

Return the repo toward a known-good state. **Selective tiers** (`scan`, `caches`, `build`, `git`, `all`) remove *artifacts* while preserving secrets, runtime deps, and skill data. **`tree`** is the destructive tier. `reset --hard` + `clean -fdx`, but **safe-by-default**: it preserves the same secrets / runtime-deps / skill-data classes unless you opt in via `--include-deps` / `--include-secrets`.

Bare invocation never mutates silently: resolve intent → dry-run → user confirmation → `--apply`. Full menu, aliases, and confirmation matrix: [context/action-router.md](context/action-router.md).

Bundled-script invocation uses two deliberate forms. Paired `${CLAUDE_SKILL_DIR}` in this file (matches `allowed-tools`) and interpreter-led `${CLAUDE_PLUGIN_ROOT}` in routed `context/*.md` detail files. Rationale: [reference/invocation-forms.md](reference/invocation-forms.md).

## Arguments

`$ARGUMENTS`. Cleanup action or alias. Resolve first:

```bash
${CLAUDE_SKILL_DIR}/scripts/resolve-clean-action.sh $ARGUMENTS
```

When a leading action token is followed by free text, the resolver also emits a `Note: <text>` line. That note is **advisory context you must address**, a question to answer (e.g. "does this include stashes?") or a live-session constraint to honor (e.g. "6-7 live sessions, mind WIP"), not part of action selection. Surface it and act on it alongside the resolved action; never silently drop it.

### Bare invocation (empty args)

1. Infer from conversation (fresh pull → `tree`, disk space → `scan`, …. See action-router).
2. If still unclear, present the action table from [context/action-router.md](context/action-router.md) and ask ([Confirmation gate](#confirmation-gate)).
3. Safest fallback: `scan`.

### Action table

| Action | Say it as… | Risk | Pre-flight? | In `all`? |
|--------|------------|------|-------------|-----------|
| `scan` | Show what's reclaimable | Safe | No | |
| `caches` | Clear tool and linter caches | Low | Yes | |
| `build` | Clear build output and logs | Low | Yes (includes caches) | |
| `git` | Prune stale git metadata; audit branches + stashes | Low | No | Yes |
| `stash` | Audit and triage stashes (age, source, diffstat) | Safe | No | |
| `tree` | Reset working tree like a fresh pull | **Destructive** | No (always dry-run first) | **Never** |
| `scan-batch` | Show what's reclaimable across many repos (skip-list) | Safe | No | |
| `tree-batch` | Reset many repos like a fresh pull (skip-list + dirty guard) | **Destructive** | No (always dry-run first) | **Never** |
| `all` | Sweep caches + build + git hygiene | Medium | Yes | |

Tiers cumulative: `build` includes `caches`. `all` = `build` + `git`. **Neither `tree` nor `tree-batch` is ever composed into `all`.**

**Fleet (batch) forms.** Each selective tier has a multi-repo form. `scan-batch`, `caches-batch`, `build-batch`, `git-batch`, `all-batch`. That runs it across a repo set (§8); all but `scan-batch` sit behind ONE gate. `scan-batch` is read-only and has no gate. `tree-batch` is the destructive tier's separate batch form (§6.5).

Aliases (`fresh`, `inventory`, `artifacts`, `caches-fleet`, …): [context/action-router.md](context/action-router.md).

## What clean NEVER touches by default

Protected-path enforcement gates `scan`, `caches`, `build`, `git`, AND `tree` (`tree` honors the same classes by default). Full list: [reference/cleanup-config.md](reference/cleanup-config.md).

- **Secrets / config**. `.env*`, `*.local.json` / `.jsonc` / `.md`, IDE user config. `tree` removes only with `--include-secrets` (UNRECOVERABLE).
- **Runtime dependencies**. `node_modules/`, `.venv/`, `vendor/`. `tree` removes only with `--include-deps` (rebuildable).
- **Skill-owned `data/`**, user-generated synthesis, always preserved; no flag removes it.

`tree` requires explicit confirmation and is never auto-invoked. Any file tracked by git is reset via `git reset --hard`, not selective deletion, and any tracked file deleted by reparse-point traversal (junction/symlink into a tracked dir) is auto-restored.

**Session-scoped destructive guard (frontmatter hook).** While this skill is active, a PreToolUse hook (`scripts/destructive-guard.sh`) inspects Bash **and** PowerShell tool calls and blocks destructive command shapes (`rm -rf`, `git clean -f*`, `git reset --hard`, `git checkout --`, `git stash drop`/`clear`, recursive `Remove-Item`, bare `git branch -D`/`-d`/`--delete`, `git push --delete`, `git push origin :ref` (also `+:ref`)). It also blocks this skill's mutating scripts (`clean-caches.sh`, `clean-build.sh`, `git-prune.sh`, `git-tree-reset.sh`, `git-tree-reset-batch.sh`, `remove-path.sh`, `clean-batch.sh`) when the command contains `--apply`, and `git worktree remove` with a force flag. A dry-run of those scripts, or of a push, is not blocked. It is a best-effort net over command text, not a security boundary: obfuscated spellings (`eval`, `bash -c`, aliases) get past it. After the [confirmation gate](#confirmation-gate) passes, re-issue the confirmed command with the acknowledgement prefix for the tool you are using: `CLEAN_GUARD_ACK=1 <command>` on the Bash tool, `$env:CLEAN_GUARD_ACK=1; <command>` on the PowerShell tool. Each spelling is a real assignment only in its own shell, so the guard accepts it only there, and only as the first statement of the command (not in a comment, a string, or after the destructive command). The gating is per tool and default-deny: any other tool name, including a missing one, gets no acknowledgement path at all, so the block stands and no prefix lifts it. Never add the prefix without the user's explicit confirmation in this session. Kill switch: the `clean_destructive_guard_enabled` userConfig option set to `false` (`/plugin configure repo-hygiene@<marketplace>`). The prefix satisfies only this guard; Claude Code's permission rules and auto-mode classifier still apply ([the host permission layer above the ack](reference/invocation-forms.md#the-host-permission-layer-above-the-ack)).

**Guard coverage for branch deletion.** The guard matches bare `git branch -D`/`-d`/`--delete`, `git push --delete`, `git push -d` and `git push origin :ref` (also `+:ref`); a push with `--dry-run`/`-n` is allowed. The ack prefix lifts these blocks like the others and is the documented way to run a bare `git branch -D` during a clean session; a spelling the patterns do not parse (a global option with a separate value such as `--work-tree <path>`, an alias) is not blocked. This skill deletes local branches with `git-branch-delete.sh` after the confirmation gate; the script deletes with `git update-ref -d`, so the confirmed path does not go through these patterns. No script or instruction this skill runs (excluding `*.test.sh` fixtures) runs `git push --delete`.

| Claim | Basis | As of | Recheck |
|---|---|---|---|
| The destructive guard matches bare `git branch -D`/`-d`/`--delete`, `git push --delete`/`-d` and `git push origin :ref` (also `+:ref`), lifted by the ack prefix; a dry-run push is allowed. | `is_destructive()` in `scripts/destructive-guard.sh`; the branch and push block cases in `scripts/destructive-guard.test.sh`. | 2026-09-29 | `is_destructive()` changes. |

## Confirmation gate

**Question surface. Every question this skill asks.** Prefer `AskUserQuestion`: its answer is the user's own and cannot be fabricated. It is not always usable, in two distinct ways, a bare-name `permissions.deny` rule or a `disallowed-tools` entry removes it from context entirely, while permission mode `dontAsk` denies it even when an allow rule names it, leaving it visible and every call failing. Fall back to the same question asked inline as a numbered choice whenever the tool is absent, denied, **or otherwise unusable**, including a denial discovered only by calling it; a denied call is an unanswered question, never an answer. Then wait for the reply. The surface varies; nothing below it does.

**Destructive confirmation. Every `--apply`, branch deletion, and stash drop.** Show the dry-run first, then take the user's own affirmative answer, given in this interactive session, naming exactly the set just shown. A prior general request, an alias, a flag, "clean everything", approval of a different set, or silence is not confirmation, never supply or infer the answer yourself. Autonomous sessions abort here rather than ask.

## Cleanup configuration

Per-tier targets: [reference/cleanup-config.md](reference/cleanup-config.md). Script binding: `scripts/lib/cleanup-paths.sh`.

## Workflow

### 0. Resolve action

Run `resolve-clean-action.sh`. If `Action: menu`, show table + ask. Otherwise dispatch to the matching § below. **Never `--apply` on first invocation.**

Resolve no repo root here. This step is reachable from anywhere, including outside a repository, and a bare `git rev-parse --show-toplevel` on that path exits non-zero and takes the menu down with it. The tiers that need a root resolve it themselves, guarded, in §§ 4 to 6 below; the bundled scripts each resolve their own and print `Error: not a git repository` rather than failing.

### 1. Scan (`scan`)

`${CLAUDE_SKILL_DIR}/scripts/scan.sh`. Read-only inventory. Stop if action is `scan`.

### 1.5. Pre-flight (caches / build / all only)

`${CLAUDE_SKILL_DIR}/scripts/preflight.sh`. `RUNTIME_PROCS` covers only the repository being cleaned; `IDE_OPEN` is machine-wide. See [context/preflight.md](context/preflight.md). Interactive: [confirm](#confirmation-gate) before `--apply` when non-empty. Autonomous: abort.

#### Dry-run → confirm → apply manifest flow (caches / build)

Both selective mutating tiers pay the filesystem walk **once**. `--dry-run` writes a session-scoped manifest and prints two machine-parseable lines: `Manifest: <path>` and `Summary: planned=N bytes=K` (bytes reclaimable. Surface this in the confirmation gate). After the user confirms, apply the **same** manifest with `CLEAN_GUARD_ACK=1 … --apply --manifest <path>`. Apply re-stats each entry (staleness guard) and removes it without re-walking, then prints `Summary: removed=N failed=M bytes=K` and exits non-zero if `failed>0`. A killed apply **resumes** by re-running the identical `--apply --manifest <path>` (already-removed entries are idempotent no-ops). `planned=` bytes can exceed `removed=` bytes when entries vanished between the dry-run and the apply; both numbers are correct. Capture `<path>` from the dry-run's `Manifest:` line and thread it through unchanged; the manifest is ephemeral (mktemp default), so pass `--manifest <path>` on the dry-run too if you need a stable location. **Build tier: repeat `--include-caches` on the apply call too**. `clean-build.sh` gates which manifest classes an apply accepts by that invocation's own `--include-caches` flag, not by what built the manifest, so an apply that omits it rejects the manifest's `caches` lines (`Rejected (wrong tier)`, `failed>0`) even though the dry-run folded them in.

### 2. Caches

`${CLAUDE_SKILL_DIR}/scripts/clean-caches.sh`, default `--dry-run`; apply per the manifest flow above (`--apply --manifest <path>`) only after confirmation.

### 3. Build (includes caches)

`${CLAUDE_SKILL_DIR}/scripts/clean-build.sh --include-caches`, default `--dry-run`; apply per the manifest flow above only after confirmation. `--include-caches` folds the caches tier into the one build manifest.

### 4. Git

**Write-safe metadata only**, not working-tree reset (that is §6 `tree`).

**Repo root for this tier** (§4 and §6 are the tiers that need one): `REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`. An empty `REPO_ROOT` means the working directory is not inside a repository: tell the user and stop this tier. Never let the resolution itself end the run.

#### 4.1 Prune and gc

`${CLAUDE_SKILL_DIR}/scripts/git-prune.sh`. `--dry-run` default; after confirmation, `CLEAN_GUARD_ACK=1 … --apply` (PowerShell: `$env:CLEAN_GUARD_ACK=1; … --apply`), per the session-scoped destructive guard above.

#### 4.2 Branch audit

`${CLAUDE_SKILL_DIR}/scripts/git-branch-audit.sh`. **Across repos** (deletes nothing): add `--repo DIR...`, `--repos-from FILE|-`, `--skip ENTRY`, `--skip-from FILE`, the same selection as §8. Each repo prints as a `Repo: <path>` block holding its usual output and its own `TipCapture:`; linked worktrees of one repo are audited once, a skipped or failing repo is reported without stopping the rest, and `--capture-file` with more than one repo is a usage error. A branch or worktree audit across many repositories, including one outside the ghq root, is `/repo-fleet-hygiene:audit` (`--root`, `--repo`), which hands per-repo cleanup back here. **Remote branches** (report only, deletes nothing): add `--remote-families` to read `refs/remotes/origin/*` by family with a retention verdict, per the remote mode in [context/git-branch-cleanup.md](context/git-branch-cleanup.md). Deletion via the [confirmation gate](#confirmation-gate) per [context/git-branch-cleanup.md](context/git-branch-cleanup.md). **Read the PR-map status line first.** `PRDataUnavailable:` means squash-merge detection did not run at all, and `PRDataTruncated:` means the map may be short. Under either line a squash-merged branch whose combined diff the patch-id proof cannot match can be classified `REVIEW` or worse, so surface the line in the confirmation gate and do not present a `SAFE`/`REVIEW` split as complete evidence. A branch whose work `git cherry`, tree equality with `origin/<default>`, or a squashed-diff patch-id finds on `origin/<default>` is `LIKELY-SAFE` with a `Landed:` line (the squash check writes one unreferenced loose object per branch it reaches, which `git gc` prunes). `MainCheckout:` and `MainCheckoutDirty:` head the report; a `MainCheckoutOperation:` / `OperationInProgress:` line means a merge, rebase, cherry-pick, revert or bisect is in progress, and then no branch is offered as deletable (`operation in progress` REVIEW) until it is finished or aborted. Branches in the `WORKTREE` tier are checked out in a linked worktree: never offer them for `git branch -d`. Invoke `/source-control:worktree cleanup --dry-run`, show its plan, let it own the removal, then re-run the audit. Branches carrying `no upstream, M commits not on origin/<default>` are never-pushed local work. Surface the count and confirm before any deletion.

**Tip capture is a precondition for deletion.** The audit prints every branch's `Tip:` and writes them all to a durable capture, `TipCapture: <path>` (under the main checkout's `.git/repo-hygiene/branch-tips/`). Deletion goes only through `${CLAUDE_SKILL_DIR}/scripts/git-branch-delete.sh --capture <that path>`, dry-run first, `--apply` after the [confirmation gate](#confirmation-gate); never a bare `git branch -d`/`-D`. The script refuses the whole batch when the capture is missing, a branch has no captured tip, a tip moved since the audit, live remote/tag reachability now loses commits the capture did not classify `LOSSY` (a `LIKELY-SAFE` row whose recorded `Landed` proof still holds when the script re-runs it is the exception: its work is on `origin/<default>` under other SHAs), or the capture's `# common_dir:` is missing or `unknown` (that field is the only check that the capture describes this repository, so an unresolved value is a refusal, not a skipped check); re-run the audit rather than deleting against a stale identifier. A `SAFE` row is a force delete only when its captured `pr` matches the audit's exact merged-PR format (`#<n> MERGED`); a `pr` that merely contains the substring MERGED still takes the ancestry check, because both columns are untrusted capture text. A `TipCaptureError:` line means no deletion can proceed from that run. Relay the script's `Restore: git branch <branch> <tip>` line to the user after every batch. Deletion stays one repo, one gate: run `git-branch-delete.sh` from inside the audited repo (any of its worktrees), with the `TipCapture:` path from that repo's `Repo:` block. It selects the repo from the working directory and refuses a capture whose `# common_dir:` is another repository's. Detail and recovery steps: [context/git-branch-cleanup.md](context/git-branch-cleanup.md) §4.7 and §4.8.

**Lossy-but-deletable branches are their own decision.** The audit's `LOSSY` tier marks a branch that is deletable but whose commits exist on no remote ref and no tag, so deleting it loses them. The boundary is the branch's `Loss:` line: a bare count is LOSSY; `none`, `undetermined (<why>)`, or an annotated count keeps the branch in REVIEW; SAFE and LIKELY-SAFE (landed proof included) are decided before the loss step and carry `not assessed`. The audit prints the LOSSY set again as its own block, `LossBlock:` through `LossBlockEnd:`, one `LossBranch:` per branch with the `LossCommit:` lines it would lose. Present that block verbatim as its own section immediately before the deletion confirmation, never only as a column in the branch table, and take a separate affirmative answer for it: a "yes" to the SAFE/LIKELY-SAFE set confirms nothing in the block. `git-branch-delete.sh` admits a LOSSY branch only under `--accept-loss` and refuses the whole batch, deleting nothing, when a LOSSY branch rides in without it. Detail: [context/git-branch-cleanup.md](context/git-branch-cleanup.md) §4.5 to §4.7.

#### 4.3 Stash audit

`${CLAUDE_SKILL_DIR}/scripts/git-stash-audit.sh`. Read-only per-stash facts (age, source branch, diffstat, PR/merge signal, advisory). **Never drops a stash.** Present the list and, for each stash, ask the user keep-or-drop ([Confirmation gate](#confirmation-gate)); a `possibly superseded` / `likely superseded` advisory is a hint to raise first, never an autonomous drop. **Across repos:** the same `--repo DIR...`, `--repos-from FILE|-`, `--skip ENTRY`, `--skip-from FILE` as §4.2 run the audit per repo as `Repo: <path>` blocks. Linked worktrees share one stash ref, so a repo whose `StashStore:` common dir was already audited is reported skipped and its stashes are listed once. When the resolved action is `stash`, run only this step. **Read the PR-map status line first.** `PRDataUnavailable:` means the PR/merge signal did not run at all, and `PRDataTruncated:` means the map may be short. Under either line a stash whose source branch actually landed can carry no `superseded` advisory, so surface the line in the confirmation gate and do not present the advisories as complete evidence for a drop.

**Dropping stashes safely.** A confirmed drop is destructive and gated by the session guard, after the user confirms, re-issue as `CLEAN_GUARD_ACK=1 git stash drop <ref>` (Bash tool) or `$env:CLEAN_GUARD_ACK=1; git stash drop <ref>` (PowerShell tool). **On the PowerShell tool a `stash@{n}` ref must be single-quoted** (`git stash drop 'stash@{0}'`): bare, pwsh reads `@{…}` as splatting syntax and git gets a mangled argument (``unknown switch `e'``) and drops nothing. A `Commit:` id needs no quoting. The `Stash:` selector (`stash@{n}`) is **volatile**: the list renumbers after every drop, so dropping more than one by selector top-down retargets the wrong entry. Drop by the stable `Commit:` id (resolve it to its current selector immediately before each drop), or drop the highest-numbered selector first so lower indices stay valid.

### 5. All

§1.5 once, then §2–§4. **Does not run §6.**

### 6. Tree (destructive)

`${CLAUDE_SKILL_DIR}/scripts/git-tree-reset.sh`, default `--dry-run`. Detail: [context/git-tree-reset.md](context/git-tree-reset.md). Default-preserve; opt-in `--include-deps` / `--include-secrets`; `--allow-unpushed` when HEAD is ahead of upstream.

**Mandatory gate:** show dry-run output → [confirmation gate](#confirmation-gate) → only then `CLEAN_GUARD_ACK=1 … --apply` (PowerShell: `$env:CLEAN_GUARD_ACK=1; … --apply`; see the session-scoped destructive guard above). Surface the dry-run's `PreserveDeps` / `PreserveSecrets` / `AheadCount` lines in the confirmation so the user knows what survives. An exit 4 (`unpushed-commits`) or non-zero `AheadCount` means HEAD has unpushed commits. Confirm loss before adding `--allow-unpushed`. Autonomous sessions: abort. Post-step: after a tree reset that removed dependencies, suggest reinstalling them with the project's own bootstrap/setup and re-validating the environment. For a truly pristine tree, close running dev tooling first (MCP servers, telemetry collectors, build/test watchers). Live processes recreate ignored dirs (`obj/`, `node_modules/`, and the like) the moment they are deleted, and may hold locks that surface as `Unremovable:`.

### 6.5. Tree batch. Multi-repo (destructive)

`${CLAUDE_SKILL_DIR}/scripts/git-tree-reset-batch.sh`, default `--dry-run`. Runs §6 `tree` across a set of repos behind one gate, with a separator-agnostic skip list and a dirty-by-default guard. Detail + examples: [context/git-tree-reset-batch.md](context/git-tree-reset-batch.md). Additive over §6, the batch layer runs no destructive git itself; each per-repo reset delegates to the unchanged `git-tree-reset.sh`, preserving every single-repo gate.

Repo sources: `--repo` (repeatable; a shell glob expands to these) and `--repos-from FILE|-` (ingests `ghq list -p` output). Skip list: `--skip ENTRY` / `--skip-from FILE` (absolute path, `owner/repo`, or bare `repo`; separator-agnostic). Passthrough to the child: `--force-default-branch` / `--include-deps` / `--include-secrets`.

**Mandatory gate (single, batch-wide):** show the `--dry-run` whole-batch plan (per-repo `Outcome`/`Reason`, the `Summary` totals, and any `UnmatchedSkip:` warnings) → [confirmation gate](#confirmation-gate) **once** → only then `CLEAN_GUARD_ACK=1 … --apply` (PowerShell: `$env:CLEAN_GUARD_ACK=1; … --apply`) **once**. Do not gate per repo. A fresh-clone fleet is typically all on the default branch, so expect an all-blocked dry-run unless `--force-default-branch`. Surface that in the confirmation. `--include-dirty` resets repos with uncommitted or untracked changes or unpushed commits, discarding that work unrecoverably; it needs its own explicit confirmation naming the dirty repos, exactly like `--include-secrets`. Autonomous sessions: abort.

### 7. Orphaned path removal (destructive, on explicit request only)

`${CLAUDE_SKILL_DIR}/scripts/remove-path.sh <target>`, default `--dry-run`. Removes a whole clone or leftover directory under the ghq root (`--root` overrides), e.g. a local clone whose upstream repository was deleted. Not composed into any tier and never inferred: run it only when the user explicitly asks to delete that path. Guards resolve paths physically and require the target to share the root's filesystem device (symlink/junction/cross-mount ancestors cannot escape containment), and refuse the containment root, symlink targets, linked worktrees (that lifecycle belongs to `git worktree remove`), any plain directory still holding nested git repos (normal, bare, or worktree), any target holding ignored skill-owned `data/` (irreplaceable. No override; move it out first), and any repo with uncommitted changes, stashes, registered worktrees, ignored secret-class files (`--include-secrets` to discard), or unpushed refs (`--allow-unpushed` to discard).

**Mandatory gate:** show dry-run output → [confirmation gate](#confirmation-gate) → only then `CLEAN_GUARD_ACK=1 … --apply` (PowerShell: `$env:CLEAN_GUARD_ACK=1; … --apply`; see the session-scoped destructive guard above). Surface `Kind` / `UnpushedRefs` / `SecretsCount` / `SkillData` in the confirmation. Autonomous sessions: abort.

**Documented boundaries.** Containment is path- and device-based (physical resolution plus a same-device check). A *same-device* `mount --bind` under the root shares the root's filesystem device, so no path-based check can detect it; closing that would require a Linux-only mount-table (`/proc/self/mountinfo`) model that would also refuse legitimate under-root mounts, so it stays out of scope for this local, dry-run-default, explicit-`--apply` tool. The unpushed-ref guard covers `refs/heads` and `refs/tags`; other locally-created namespaces (e.g. `refs/notes`) are not scanned, and auto-generated ones (`refs/prefetch/*` from git-maintenance, `refs/replace/*`) are intentionally not treated as unpushed. `--allow-unpushed` is the escape hatch for any local ref. The secret scan gates only ignored (unrecoverable) files; tracked files are git's domain (recoverable via reset/remote, and separately blocked when dirty or unpushed).

### 8. Batch. Multi-repo selective tiers (`scan-batch` / `caches-batch` / `build-batch` / `git-batch` / `all-batch`)

`${CLAUDE_SKILL_DIR}/scripts/clean-batch.sh --tier <scan|caches|build|git|all>`, default `--dry-run`. Runs the §2–§5 selective tiers across a set of repos behind one gate, the selective-tier sibling of §6.5 `tree-batch`. Detail + examples: [context/clean-batch.md](context/clean-batch.md). Additive over the single-repo tiers, the batch layer runs no removal itself; each per-repo action delegates to the unchanged child (`clean-caches.sh` / `clean-build.sh` / `git-prune.sh`), preserving every child gate. **`tree` is not batched here** (use §6.5); **audits run across repos and delete nothing; deletion stays one repo, one gate** (`git-branch-audit.sh` and `git-stash-audit.sh` take the same repo and skip flags, §4.2 and §4.3; `git-branch-delete.sh` is never batched; an audit across many repositories, including one outside the ghq root, is `/repo-fleet-hygiene:audit`). Batch `git` is prune/gc/remote-prune only, once per unique shared object store.

Repo sources: `--repo` (repeatable; a shell glob expands to these) and `--repos-from FILE|-` (ingests `ghq list -p`; backslash paths normalized). Skip list: `--skip ENTRY` / `--skip-from FILE` (same separator-agnostic matcher as `tree-batch`).

**Mandatory gate (single, batch-wide):** run `--dry-run` once → it writes a **batch plan** and prints `BatchPlan: <path>`, per-repo `Outcome`/`Reason` (`nothing-to-do` for a repo with no paths to remove and no new shared object store), a `Repo | Outcome | Paths | Bytes` table, any `UnmatchedSkip:`, and an aggregate `Summary: repos=N planned=P bytes=K` (surface the reclaimable `bytes`). For `caches`, `build`, and `all` it also runs `preflight.sh` **once** before the repo loop (not per repo) and prints `PreflightScope: batch-repositories` plus the preflight facts, with `RECENT_BUILD` scanned across every batch repository; the git-only tier skips that. `Progress:` lines go to stderr (`N/M <path>` on dry-run, `apply N <path>` on apply) so a long fleet run is not silent. Apply does not re-run preflight, so the preflight facts (`RUNTIME_PROCS`, `IDE_OPEN`, `RECENT_BUILD`) are as of the dry-run; after a long gap run `preflight.sh` again before confirming. [Confirmation gate](#confirmation-gate) **once** → then `CLEAN_GUARD_ACK=1 … --apply --batch-plan <path>` **once**. `--batch-plan FILE` is also accepted with `--dry-run`, to pick a stable plan path. The plan IS the gated set: apply targets exactly those repos (`--apply` errors without `--batch-plan`), so a repo that vanished after the dry-run applies idempotently and one that appeared is never touched. Apply prints `Summary: removed=N failed=M bytes=K` and exits non-zero on any failure. Autonomous sessions: abort.

**`--tier scan` (`scan-batch`) is read-only.** It runs the unchanged `scan.sh` per repo, writes no batch plan, and takes no `--apply` or `--batch-plan` (either is a usage error, exit 2), so it needs no confirmation gate. It prints per-repo `Outcome: scanned` and `Summary: repos=N planned=0 bytes=K`, K the summed `Total reclaimable`; run `scan.sh` inside one repo for its per-path inventory.

## Integration

| Surface | Relationship |
|-------|-------------|
| `/source-control:worktree cleanup --dry-run` | Removes git worktree directories, not in-place reset; the `git` action invokes it for `WORKTREE` branches and re-audits afterward |
| `/repo-fleet-hygiene:sync` | Realigns a canonical clone that is off the default branch; the `git` action presents it, never invokes it |
| The project's build / verify workflow | Rebuild after `build` or `tree` |
| The project's bootstrap/setup | Restore dependencies after `tree` |
| The project's environment-validation tooling | Full env validation after `tree` or `all` |
