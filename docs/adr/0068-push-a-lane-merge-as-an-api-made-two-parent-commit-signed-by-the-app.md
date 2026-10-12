# Push a lane merge as an API-made two-parent commit signed by the App

- Status: accepted
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
   that can write ([`pr-pipeline.schema.json:171-186`](../conventions/pr-pipeline/pr-pipeline.schema.json),
   [`resolve.mjs:198-207`](../../.github/actions/resolve-config/resolve.mjs)). The write runner
   branches on the resolved `prepare` output, never on the skill's name.
2. Before any model turn, the base's `prepare.sh` runs `git merge --no-commit --no-ff` of the
   trusted base ([ADR 0069](0069-trust-the-default-branch-tip-for-a-conflicting-pr.md)) into the
   gated head ([`pr-run-activity-write.yml:424-494`](../../.github/workflows/pr-run-activity-write.yml)).
   A clean merge takes no model turn; the skill runs only on a conflicted one.
3. After the skill, the base's `post.sh` checks the index and writes it as a tree
   (`pr-run-activity-write.yml:688-741`).
4. A pinned `github-script` step uploads only the blobs neither parent holds, builds the tree,
   fails unless GitHub's tree hashes to `post.sh`'s, and creates the commit with
   `parents: [gated head, trusted base]` and no author, committer or signature fields, so GitHub
   signs it as the App. It writes the commit to the lane branch with `force: false`
   (`pr-run-activity-write.yml:742-891`).
5. The existing promote step fast-forwards the PR branch only when the lane branch holds that
   step's own commit and the PR branch is still at the gated head, then re-reads the ref to confirm
   the move (`pr-run-activity-write.yml:893-950`).

## Alternatives considered

- **`git push` of the local merge commit.** Rejected: unsigned, so `check-signed-commits` fails
  it, and it bypasses the promote step's head-moved guard.
- **The existing commit tool on the lane branch.** Rejected: it makes a single-parent commit, so
  the PR stays computed against the old base.
- **A separate push job with its own mint.** Rejected for now: it is the fix-ci head-code and push
  split the owner has reserved, and it costs a second mint per run.

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
- The merge scripts need git 2.41 or later (`GIT_ATTR_SOURCE`) and fail closed below it.
