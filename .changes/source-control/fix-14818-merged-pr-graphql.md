---
bump: patch
---

### Fixed

- `landed-work.sh --merged-pr-proof` reads merged pull requests again. The listing asked `gh pr list` for `commits`, which gh expands with each commit's authors, so GitHub refused the query at any limit of 50 or more (more than 500,000 possible nodes) and every worktree stayed unproven with `merged-pr-read-failed:gh-pr-list (GraphQL: ...)`. It now pages a `gh api graphql` query that reads only the head and base refs, the head oid and each PR's commit oids, 100 PRs a page, until `--merged-pr-limit` PRs are read. The stderr gh call count counts each page.
