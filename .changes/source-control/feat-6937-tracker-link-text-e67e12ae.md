---
bump: minor
---

### Added

- **`/source-control:pull-request create` takes the PR's link line from the bound work-item tracker.** With the `work-items` plugin installed and a tracker bound, it resolves the branch's item through `/work-items:track link`, so a Jira or Linear binding gets that tracker's link text; without a binding the GitHub `Closes #N` default is unchanged. `parse-branch-issue.sh` accepts a tracker key (`SW2-1234`) as well as an issue number, and a `--no-default` mode that leaves the default grammar to the tracker's adapter.
