---
bump: patch
---

### Fixed

- **The `quality-gate` PR mode gates the bundled `/code-review` by effect, not by a fixed flag list.** The list had gone stale: the command gained arguments that post to the pull request or hand the review to a cloud run. Any invocation whose arguments edit the working tree, post, or run in the cloud now needs explicit opt-in, and only a report-only run stays ungated. The managed Code Review service's availability, which now excludes more organization configurations, is read live instead of listed, and the bundled command is no longer called always available.

### Changed

- **Copied upstream specifics in the review records become anchored pointer records.** The bundled `code-review` and native `security-review` records, the `security-review` CI-failure note and frontmatter gotcha, and the Claude Security deep-scan escalation in `quality-gate` and `fanout` point at the live section that owns each fact, with an as-of date and a recheck trigger. The `fanout` escalation defers to the `quality-gate` record instead of carrying its own link. `explain-change` states its publish gate as its own rule rather than resting it on Artifact tool behavior.
