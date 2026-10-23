---
bump: patch
---

### Changed

- The pr-merge gate accepts a verdict artifact named `pr-verify-<pr>-<sha>-<verdict>-<ref-digest>`, the digest being the first `babysit_verify_evidence.HEAD_REF_DIGEST_HEX` (16) hex digits of the SHA-256 of the head branch the verdict records. For an untied FAIL so named, the gate ties it to the pull request from the name instead of downloading its verdict.json; a name without the digest is downloaded and read as before. One decision changes: a digest-named untied FAIL whose verdict.json cannot be read used to refuse `verify:unreadable`, and now its name decides. That is safe because the name is trusted only from a run of verifier origin, the same check that authenticates the verdict.json, and because equal branches always give equal digests, so a collision can only tie a FAIL, never untie one. pr-verify still writes the name without the digest; a later change switches it once this reader has run on main.
