---
bump: patch
---

### Changed

- The pr-merge gate reads the head branch an untied FAIL records from the head-ref digest in its artifact name (`pr-verify-<pr>-<sha>-<verdict>-<16 hex digits of the SHA-256 of head_ref>`, `babysit_verify_evidence.HEAD_REF_DIGEST_HEX`) instead of downloading its verdict.json. A name without the digest, uploaded before it was added, is still downloaded and read as before. The name is trusted only from a run of verifier origin, as the verdict.json is, and equal branches always give equal digests, so a collision can only tie a FAIL to a branch, never untie one. No gate decision changes.
