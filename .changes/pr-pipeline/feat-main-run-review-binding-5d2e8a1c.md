---
bump: minor
---

### Added

- `pr-review-main.yml` runs both review lanes from main, through `workflow_run` on `pr-require-checks`, for a pull request that changes a lane source (a workflow, Claude Code configuration or the review criteria). It reviews the head's diff as data with each lane's criteria copied from main, on a read-only token and a Read-only model leg, posts nothing, and uploads each lane's verdict as `pr-review-main-<lane>-<pr>-<tree>`. The merge gate binds such a pull request's lanes only on that verdict, authenticated by its run's record (the file, event `workflow_run`, the default branch, completed success), never on a comment; with none they stay unbound as before.
- A workflow change that gains a write scope (or leaves a job on the repository-default token) holds for a person as `permission-widening-review`, and one that adds a `pull_request_target` or `workflow_run` trigger as `privileged-trigger-review`.

### Changed

- Every workflow whose token can write, that names a secret other than `GITHUB_TOKEN`, or that mints a lane token, and the review workflows, is a `gate` floor path, held for a person: `pr-merge.yml`, `pr-require-checks.yml` and `pr-unblock.yml` move from `enforcement`. `review-path-unbindable` is gone: an enforcement path beside a lane source waits for the main-run security review.
