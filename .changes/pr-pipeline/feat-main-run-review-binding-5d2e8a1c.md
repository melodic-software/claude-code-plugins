---
bump: minor
---

### Added

- `pr-review-main.yml` runs both review lanes from main, through `workflow_run` on `pr-require-checks`, for a pull request that changes a lane source (a workflow, Claude Code configuration or the review criteria). It reviews the head's diff as data with each lane's criteria copied from main, on a read-only token and a Read-only model leg, posts only its counts as a check run, and uploads each lane's verdict as `pr-review-main-<lane>-<pr>-<tree>`. The merge gate binds such a pull request's lanes only on that verdict, authenticated by its run's record (the file, event `workflow_run`, the default branch, completed success), never on a comment; with none they stay unbound as before.
- A workflow change that gains a write scope (or leaves a job on the repository-default token) holds for a person as `permission-widening-review`, and one that adds a `pull_request_target`, `workflow_run`, issue, comment, review, discussion or `repository_dispatch` trigger as `privileged-trigger-review`.
- A file the files API sends no patch for holds for a person as `unreviewed-patch:<path>` unless it is an image, font or PDF. The main-run review diffs with `--text` and writes no verdict for a binary or over-size patch.
- The main-run review records each lane's counts as a `pr-review-main: <lane>` check run, which no token can delete; the gate holds on the most CRITICAL findings any head of the pull request recorded, so a whitespace push cannot re-roll one away.

### Changed

- Every workflow that holds a credential beyond its job's `GITHUB_TOKEN` (a secret other than `GITHUB_TOKEN`, a lane token, an OIDC token), and the review workflows with the main-run review's scripts, is a `gate` floor path, held for a person; `scripts/sync-hold-floor.py` derives the workflow rows from the files. Claude Code settings, `.mcp.json`, `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` and `docs/standards/**` are `gate` too. `pr-merge.yml` and `pr-unblock.yml` move from `enforcement`; `pr-require-checks.yml` stays `enforcement`. `review-path-unbindable` is gone: an enforcement path beside a lane source waits for the main-run security review.
- Those review-surface `gate` rows (the gated workflows, the main-run review's scripts, the agent settings and instruction files) never take a trusted author's gate-path lift; a person approves them.
- The main-run review reads its diff in parts one Read returns whole, and writes a verdict only when every part was read whole.
- Without PyYAML, a mapping-form `issues:` trigger under `on:` holds as `privileged-trigger-review`.
- `**/.claude/hooks/**` is a `gate` floor path outside the author lift: a hook that settings already registers changes what lanes run.
