---
bump: minor
---

### Fixed

- hold trust-gate path changes the agent App authored or pushed

  ci-status's trust-gate path hold covered only the exempt authors (Dependabot, the release App, the standards-sync App). A pull request the agent App opened, or one it wrote a commit of or pushed to, went to the review lanes, whose callers its head can rewrite. The new `merge.trust-path-hold-apps` key in `pr-pipeline.yaml` lists such Apps by `[bot]` login (this repository: `melodic-agent[bot]`), read at the base commit. A same-repository pull request that changes a trust-gate path now fails ci-status, and a person merges it, when a listed App is its author, the author or committer of one of its commits (account or noreply address), or a pusher to its head branch (the repository activity API). It still needs both review lanes otherwise. The App list, commits and push history are read only once a trust-gate path matched; an unreadable one, a commit list shorter than the pull request, or a full page of pushes fails closed.
