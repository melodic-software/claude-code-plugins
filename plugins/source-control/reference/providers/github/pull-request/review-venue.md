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
| `security-review` | `melodic-software/ci-workflows/.github/workflows/pr-review-security.yml@<sha>` |

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
gh api "repos/{owner}/{repo}/actions/workflows/<workflow_id>/runs?per_page=100"
```

Runs come newest first. The script takes the first with `status` `completed` and a `conclusion`
other than `skipped` (a draft, or an actor the lane does not admit) and `cancelled` (a newer push
superseded it), then compares its `created_at` with the window. A usage-limit stop exits the lane
job non-zero, so its run concludes `failure`.
