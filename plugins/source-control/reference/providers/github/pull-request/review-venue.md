# GitHub: review venue

The GitHub facts behind the pull-request skill's
[review venue](../../../../skills/pull-request/reference/review-venue.md). That file owns the rule
and what each line means; this one says how `scripts/review-venue.sh` reads GitHub.

## Which workflows are lanes

A lane is a caller workflow whose pull request runs reference one of the org's reusable review
workflows, fixed in the script:

| Lane | Reusable workflow the caller's runs reference |
|---|---|
| `code-review` | `melodic-software/ci-workflows/.github/workflows/pr-review.yml@<sha>` |
| `security-review` | `melodic-software/ci-workflows/.github/workflows/pr-review-security.yml@<sha>`, or `pr-review-cli.yml@<sha>` from a caller whose path contains `security` (the run listing does not show its `lane` input) |

The caller's own file name does not matter (`pr-review-hosted.yml` on a public repository,
`pr-review.yml` on a private one). The script reads the `referenced_workflows` field of the
repository's newest pull request runs, up to three pages of 100:

```bash
gh api "repos/{owner}/{repo}/actions/runs?event=pull_request&per_page=100&page=1"
```

The caller job skips a draft, and a skipped run still lists the reusable workflow, so a repository
with lanes shows them on the first page in practice. Pointer: the run object's fields are read at
[REST API: list workflow runs for a repository](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository).
As of: 2026-10-17, read from live responses on `melodic-software/claude-code-plugins` and
`melodic-software/standards`. Recheck trigger: a run response stops carrying
`referenced_workflows`, or the lanes move to a reusable workflow at another path.

## The lane's newest verdict

```bash
gh api "repos/{owner}/{repo}/actions/workflows/<workflow_id>"
gh api "repos/{owner}/{repo}/actions/workflows/<workflow_id>/runs?event=pull_request&per_page=100"
```

The first read gives the workflow's `state`. Any value but `active` reads `local absent`: a
disabled workflow keeps its run history but runs on no trigger. The second lists only pull request
runs, so a manual or scheduled run of the same workflow cannot mask a failing pull request run.
Pointer: `state` and its values are read at
[REST API: get a workflow](https://docs.github.com/en/rest/actions/workflows#get-a-workflow), the
`event` filter at
[REST API: list workflow runs for a workflow](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow).
As of: 2026-10-17. Recheck trigger: either section renames `state` or `event`, or changes what
`active` means.

Runs come newest first. The script takes the first with `status` `completed` and a `conclusion`
other than `skipped` (a draft, or an actor the lane does not admit) and `cancelled` (a newer push
superseded it), then compares its `created_at` with the window. A usage-limit stop exits the lane
job non-zero, so its run concludes `failure`.

A run that did not succeed gets two more reads before it counts:

```bash
gh api "repos/{owner}/{repo}/actions/runs/<run_id>/jobs?per_page=100"
gh api "repos/{owner}/{repo}/check-runs/<job_id>/annotations?per_page=100"
```

A job's `id` is its check run's id. When every failed or timed-out job carries a `failure`
annotation whose message starts `failure-class=skipped-validation`, the pull request edited the
caller workflow, claude-code-action skipped itself, and the run is passed over like a skipped one.
Any other class, `rate-limit` included, or a failed run with no failed job, keeps its verdict.
After 10 such runs in a row the lane reads `local stale`. Pointer: the annotation is the reusable
workflow's last step, `echo "::error title=$LANE failed::failure-class=..."`, in
[ci-workflows `pr-review.yml`](https://github.com/melodic-software/ci-workflows/blob/main/.github/workflows/pr-review.yml)
and `pr-review-security.yml` (`pr-review-cli.yml`'s publish step writes it after the lane id, `<lane>: failure-class=...`); the reads are at
[REST API: list jobs for a workflow run](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run)
and [REST API: list check run annotations](https://docs.github.com/en/rest/checks/runs#list-check-run-annotations).
As of: 2026-10-21, read from runs 39610040287 and 39610040502. Recheck trigger: the reusable
workflows rename `failure-class` or `skipped-validation`, or stop writing the class as an
annotation.
