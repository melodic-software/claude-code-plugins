---
bump: patch
---

- **Fixed:** `/work-items:triage --ci` acted on no recorded decision: it cannot make the write-access read the attended steps ask before a comment counts, so it held every `**Decision recorded.**` comment as unverified. CI mode now takes a comment in `issue.json` as passing that test when the repository's `## Triage rules` state that the lane keeps only trusted authors' comments; without that statement every comment stays a claim to verify.
