# Push a lane merge as an API-made two-parent commit signed by the App

- Status: accepted; the commit moves to a script job with its own mint 2026-10-23 (see the
  [addendum](#addendum-2026-10-23-a-script-job-commits-the-merge-and-the-model-holds-no-write-token))
- Date: 2026-10-12

## Context

The pr-unblock lane's `resolve-conflicts` activity merges the default branch into a PR head and
resolves the conflicts. The result must reach the PR branch as a real merge, so GitHub computes the
PR against the new base, and it must pass the pipeline's commit rules: every lane commit after the
gated head is verified, or the report job's `check-signed-commits` fails the activity
([ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md),
[ADR 0054](0054-keep-commit-signing-on-the-default-branch-rule-and-add-no-all-branch-rule.md)), and
the PR branch moves only by fast-forward from the gated head. The lane's existing commit tool
writes single-parent commits, and the App token never holds `workflows`.

GitHub marks a bot commit made through the API verified only when "the request is verified and
authenticated as the GitHub App or bot" and "contains no custom author information, custom
committer information, and no custom signature information"
([About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification),
fetched 2026-10-12).

## Decision

The runner, not the model, makes the merge commit through the Git Data API
([pr-run-activity.md, "prepare: merge-base"](../conventions/pr-pipeline/pr-run-activity.md#prepare-merge-base)):

1. A leaf opts in with `prepare: merge-base`, a closed-enum schema key valid only on a skill leaf
   that can write. The write runner branches on the resolved `prepare` output, never on the
   skill's name. Basis:
   [`pr-pipeline.schema.json:171-186`](../conventions/pr-pipeline/pr-pipeline.schema.json);
   [`resolve.mjs:198-207`](../../.github/actions/resolve-config/resolve.mjs);
   [`pr-run-activity-write.yml:359,434`](../../.github/workflows/pr-run-activity-write.yml).
2. Before any model turn, the base's `prepare.sh` runs `git merge --no-commit --no-ff` of the
   trusted base ([ADR 0069](0069-trust-the-default-branch-tip-for-a-conflicting-pr.md)) into the
   gated head. A clean merge takes no model turn; the skill runs only on a conflicted one. Basis:
   `pr-run-activity-write.yml:424-494,527`.
3. After the skill, the base's `post.sh` checks the index and writes it as a tree. Basis:
   `pr-run-activity-write.yml:688-741`.
4. A pinned `github-script` step uploads only the blobs neither parent holds, builds the tree,
   fails unless GitHub's tree hashes to `post.sh`'s, and creates the commit with
   `parents: [gated head, trusted base]` and no author, committer or signature fields, so GitHub
   signs it as the App. It writes the commit to the lane branch with `force: false`. Basis:
   `pr-run-activity-write.yml:742-891`; the GitHub page quoted in Context.
5. The existing promote step fast-forwards the PR branch only when the lane branch holds that
   step's own commit and the PR branch is still at the gated head, then re-reads the ref to confirm
   the move. Basis: `pr-run-activity-write.yml:893-950`.

## Alternatives considered

- **`git push` of the local merge commit.** Rejected: unsigned, so `check-signed-commits` fails
  it, and it bypasses the promote step's head-moved guard. Basis: ADR 0054, "Decision";
  `pr-run-activity-write.yml:893-950`.
- **The existing commit tool on the lane branch.** Rejected: it makes a single-parent commit, so
  the PR stays computed against the old base. Basis: judgment; the tool was not re-read for this
  record.
- **A separate push job with its own mint.** Rejected for now: it is the fix-ci head-code and push
  split the owner has reserved, and it costs a second mint per run. Basis:
  [ADR 0058](0058-mint-lane-app-tokens-through-an-oidc-broker.md) point 3 (one mint per job); the
  owner's reservation of that split is not recorded in this repository.

## Consequences

- The first parent is the gated head, so the fast-forward guard is unchanged, and the commit is
  verified: sandbox probe run 38148710292 produced a verified two-parent commit that passed
  `check-signed-commits`, and the lane's first sandbox merge (run 38180382216, commit
  `b7df9578d3`) had `parents[1]` equal to the trusted base.
- The commit step also checks GitHub's tree hash against `post.sh`'s tree and every uploaded
  blob, and the promote step refuses a lane-branch commit the commit step did not make, because
  the model holds a contents-write token
  ([#7225](https://github.com/melodic-software/claude-code-plugins/pull/7225)).
- Accepted residual: a `.github/workflows/` change from the base side of a merge, neither
  conflicted nor staged by the model, is committed and pushed. GitHub did not refuse it for the
  App's missing `workflows` permission (probe run 38148710292, all three push methods). A
  conflicted or model-staged workflow path escalates instead.
- The merge scripts need git 2.41 or later (`GIT_ATTR_SOURCE`) and fail closed below it. Basis:
  [`prepare.sh:24,79`](../../.github/scripts/merge-base/prepare.sh).

## Addendum (2026-10-23): a script job commits the merge, and the model holds no write token

The rejected alternative "a separate push job with its own mint" is now the decision: the model
job no longer holds `contents: write` or runs git, and the commit Decision describes is made by
`apply-conflict-patch`, a `prepare: apply-patch` script job, through
[`apply-patch.mjs`](../../.github/scripts/apply-patch/apply-patch.mjs) under
`patch-rules.json`'s `merge-base` row. The commit is still made through the Git Data API with no
author, committer or signature, parents `[gated head, trusted base]`, the trailer the repeat cap
counts, and only the blobs `tree-entries.sh` flags uploaded; its tree is still checked against
GitHub's.

- **Three merges, one conflict tree.** `resolve-conflicts-select` (base code, read-only token) pins
  the default branch tip and merges it with `prepare.sh`, which also prints the conflict tree T0.
  The read runner and the push job each merge that pinned base again and fail red unless they
  reach the same state and T0. A merge recomputed by `git merge-tree` was not used, since the
  version-bump script needs a merge in progress (it reads `MERGE_HEAD`).
- **The model edits files, not the index.** The skill runs on `run-claude-cli` with no Bash,
  reads `.lane/merge/` (each conflicted path's stages and both sides' history, written by
  `context.sh`), and resolves in place. Its edits leave as a patch measured from T0, so the patch
  holds them alone.
- **The push job admits only resolutions.** Only the patch's own changes face the refusals,
  `max-files` and the `merge-result` predicate (a path the merge left conflicted); every
  conflicted path left in the tree must be marker-free, and a `.github/workflows/` change must be
  exactly the base's, as `post.sh` held it before. The base-side changes pass through. A merge that
  needs more than `max-blobs` new blobs is refused before any write.
- The accepted residual above stands; `apply-conflict-patch` has not been probed on that shape.
