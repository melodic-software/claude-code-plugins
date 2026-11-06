---
bump: patch
---

### Changed

- The merge-risk rating runs behind the pr-verify key's credit gate, on `PR_VERIFY_CLAUDE_API_KEY`, then `PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN` on a handoff, then `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, instead of the key alone.
