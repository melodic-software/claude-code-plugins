---
bump: patch
---

### Fixed

- **babysit-prs**: the pr-verify verdict reader reads a short incremental artifact listing again after a wait when no whole listing fits the caller's limit, instead of falling back to a whole listing that can only refuse. Under the dispatchers' FAIL-cap reads at about 13,600 artifacts, that fallback refused the PR's round after spending its reads. A listing is still kept only when it holds GitHub's live count.
