---
bump: patch
---

### Changed

- Every reader of a pr-verify verdict name (the pr-merge gate, the resolver, the FAIL-notes poster `verify-notes.mjs` and pr-feedback-dispatch) also accepts the name followed by `-<ref-digest>`, the first 16 hex digits of the SHA-256 of the head branch the verdict records (`headRefDigest` in `write-verdict.mjs`). The gate ties an untied FAIL from such a name without downloading it, so a digest-named FAIL whose verdict.json cannot be read no longer refuses `verify:unreadable`. `verify-notes.mjs` checks the digest against the verdict. pr-verify still uploads the old name until a follow-up switches the writer.
