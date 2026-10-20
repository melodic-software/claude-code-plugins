---
bump: minor
---

### Added

- **`block-fix-request-post`: an agent can no longer post the PR-fix lane fix request (#8438).** The address-feedback lane acts, with push credentials, on a comment line starting `PR-fix lane: please fix this finding` from someone with write access, and a local session posts with the owner's token. The guard blocks that line in `gh pr|issue comment|review|create|edit`, a writing `gh api` (GraphQL only for a mutation), `curl` with a body to a GitHub API route, and the GitHub MCP server's comment, review, issue and pull-request write tools. It reads the body inline, from heredocs, and from body files (`--body-file`, `-F k=@file`, `--input`, `-d @file`, `cat`, `<`). A line after `>`, inside a fence, or a mention later in a line passes, as does a command that only reads or greps the phrase. On by default; `block_fix_request_post_enabled` turns it off.
