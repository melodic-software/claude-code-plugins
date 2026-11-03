# 2.7 `create --pushed`: PR-only entry for an orchestrated flow

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

`create --pushed --worktree <path>` opens the PR when the branch is **already committed and pushed**: a dispatched worker did the edits, commit, and push in its own out-of-tree worktree and returned that worktree's path (`/work-items:work`). The orchestrator is typically **out-of-tree** (on the default branch or elsewhere), so this mode skips the commit/push half of the normal `create` path and does not trust the session cwd.

**Ignore the gathered repository context.** [SKILL.md](../SKILL.md)'s gather step (`git branch --show-current`, `git diff --name-only HEAD`, working-tree status) reports the **session cwd**, the wrong branch and diff for an out-of-tree orchestrator. Do not `git -C`-redirect those calls ad hoc; under `--pushed`, re-resolve everything from the target worktree explicitly:

```bash
WT="<path>"                                   # from --worktree
BRANCH=$(git -C "$WT" branch --show-current)
```

**Preconditions (assert, never redo).** The worker commits, pushes, and brings the branch current with the default branch before returning; verify rather than repeat:

- **Clean tree:** `git -C "$WT" status --porcelain` empty, else STOP (the worker returned with uncommitted work).
- **Pushed to the remote at HEAD:** confirm the branch's remote tip equals local HEAD **without relying on `@{u}`**: a worker that pushed with `git push origin <branch>` (no `-u`) has no upstream, so `git log @{u}..` exits 128 on a fully pushed branch. Resolve the remote and compare the refs directly:

  ```bash
  # Resolve the PUSH remote (the destination the worker pushed to) via the shared
  # resolver in --push mode, run FROM the worktree so it reads $BRANCH's config —
  # never a hardcoded `origin`, so a `git clone -o vendor` or a triangular fork
  # flow (fetch upstream, push fork) verifies the ref at the right destination.
  REMOTE=$( cd "$WT" && bash "<skill-dir>/scripts/resolve-remote.sh" --push ) || exit 1
  git -C "$WT" fetch -q "$REMOTE" "$BRANCH"
  [ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$WT" rev-parse FETCH_HEAD)" ] \
    || { echo 'worker branch is not fully pushed to the remote' >&2; exit 1; }
  ```

  else STOP (the worker returned without pushing HEAD).

**Caller requests.** The orchestrator asks through two optional flags after `--worktree`:

- `--draft '<reason>'` is [§2.4.3](create-open-pr.md)'s request level, the same flag the normal `create` path takes,
  for example `Draft: merge hold unread`.
- `--hold '<line>'` takes a line starting `Hold:`, which [§2.4.1](create-push-and-body.md)'s body composition places
  directly below `${CLOSES_LINE}` in `$BODY_FILE` before the [§2.4.2](create-gate.md) gates run, so the PR opens
  with the hold before `ready --unattended` can flip it. A value not starting `Hold:` is refused:
  STOP and report it.

**Sub-steps relative to the normal `create` path:**

- **[§2.1](create-preflight.md) / [§2.3](create-commit.md) (branch-name prompts, stage + commit):** skipped. The worker already committed; the preconditions above replace them.
- **[§2.2](create-rebase.md) (rebase onto the default branch):** skipped. The worker brings the branch current before returning; the Phase 3 mergeability read and CI catch residual staleness. The out-of-tree orchestrator cannot rebase a branch it is not on, so it never owns this step.
- **§2.4.1 (push):** skipped, replaced by the unpushed-commits assertion above, except §2.4.1's base merge: when it applies and `$BRANCH` is behind `$BASE`, merge in `$WT` (`git -C "$WT"`, the fetch remote from `resolve-remote.sh` without `--push` run from `$WT`, `$BASE` resolved as the §2.4.3 bullet below says, before the merge) and push it with `push-branch.sh --dir "$WT"`. When the merge conflicts, run `git -C "$WT" merge --abort`, so `$WT` returns to the worker's clean tree, then STOP and report the conflict: no push and no PR create, since this unattended run has no PR to leave in draft and cannot resolve the conflict itself.
- **[§2.4.0](create-linked-issue.md) (`Closes #N`), §2.4.1 (body assembly), §2.4.2 (pre-create gates):** run unchanged, except every `git`/diff read is anchored with `git -C "$WT"` and the branch is `$BRANCH`, never the session branch. In §2.4.0 this means passing `$BRANCH` as `parse-branch-issue.sh`'s explicit first positional and running it with `CLAUDE_PROJECT_DIR="$WT"` (`CLAUDE_PROJECT_DIR="$WT" parse-branch-issue.sh "$BRANCH" ['<branch-issue-pattern>']`), so it reads the worktree's own `source-control.md` layers, not the orchestrator's. The script defaults to `git branch --show-current` **in its own process**, which `git -C` cannot redirect, so leaving it implicit would parse `Closes #N` from the orchestrator's branch and silently drop the linkage.
- **§2.4.3 (create):** the PR create MUST name the head `$BRANCH` explicitly, since the invoker is not on the branch ([GitHub](../../../reference/providers/github/pull-request/create.md#open-the-pr-from-an-out-of-tree-orchestrator)). §2.4.3's open-state step reads `docs/conventions/source-control.yaml` at the PR's base branch, never from `$WT` or the worker's branch. A `--pushed` run is unattended but follows the resolved state: a resolved `ready` runs Phase 2.5 as `ready "$PR_NUMBER" --unattended`, whose holds still apply. It runs with `$WT` as its working directory: every Phase 2.5 command takes the `( cd "$WT" && … )` form this section uses for `resolve-remote.sh`, and every forge call names `$PR_NUMBER`, the PR this run just opened. It stops when the branch in `$WT` resolves a different PR. Its code and security reviews run in fresh-context subagents at their own model binding ([ready-for-review.md](ready-for-review.md) §2.5.3); a caller that needs the base merge and the fixes at a stronger tier invokes `create --pushed` from an agent dispatched at that tier.

  In a sandboxed session that 403s, substitute §2.4.3's REST form and anchor it, because the `{owner}`/`{repo}` placeholders expand from the current directory, which here is not the target repository. Run it from the worktree, in the subshell form this section uses for `resolve-remote.sh`.

  `$BASE` needs its own resolution: §2.2 is skipped in this mode, so nothing set a default branch. Resolve it the same anchored way.

  **On a triangular flow, anchoring to the worktree is not enough.** Where the worker pushed to a fork and the PR targets an upstream base, the placeholders resolve against the worktree's own remotes, so the REST create can silently post to the **fork**, opening a PR against the fork's default branch instead of upstream. Name the base repository (the PR's target, not the push destination) explicitly and namespace `head` as `<fork-owner>:$BRANCH`, per §2.4.3. Resolve `$BASE` against that base repository too, never through the worktree-anchored form, which would read the fork's default branch. The provider reference holds each of these commands.

- **[§2.5](create-ci-workflows.md) / [§2.6](create-report.md):** record expected workflows, report the PR URL + number, and stop. §2.6's arming step is skipped: the watch is session-scoped ([monitor-auto-watch.md](monitor-auto-watch.md) §3.0.1), so it belongs to the session acting on the events.

This mode is create-only: it never merges, and hands monitoring back to the calling orchestrator, which arms event delivery for the returned PR number through [monitor.md](monitor.md)'s Monitor entry checklist, in the session it monitors from.
