---
bump: patch
---

### Fixed

- `check-signed-commits`' escalation comment opens with `<!-- check-signed-commits hold -->` (`SIGNED_COMMITS_HOLD` in `gate-source.mjs`). A `github-actions[bot]` comment carrying it, written or edited since the human-gated label was last removed, now holds the PR: `gateSource` reads it as `signed-commits-hold`, so fix-ci, fix-docs and resolve-conflicts no longer work past the label when a lane escalation put it on first, address-feedback works only threads a trusted person asked it to fix, and `clear-escalations.mjs` keeps the label. The marker from any other account is not read, and an unmarked bot comment still holds nothing (#9578).
