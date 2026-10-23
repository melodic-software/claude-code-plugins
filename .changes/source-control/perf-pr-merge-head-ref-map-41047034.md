---
bump: patch
---

### Changed

- The pr-merge gate's verdict reader takes an untied FAIL's recorded head branch from the head-ref map pr-merge.yml names in `BABYSIT_VERIFY_HEAD_REFS` before downloading the artifact: artifact id to the `head_ref` an earlier run read from that artifact's verdict.json. An id the map holds ties or unties the FAIL as the download would, with no request; any other id is downloaded as before. A missing, unreadable or malformed map (another version or repository, a key that is no artifact id, a value that is no string) is no map, and every untied FAIL is downloaded. The decision differs from a download only where the download fails: the map answers with what an earlier successful download read, where the failed download refused `verify:unreadable`.
