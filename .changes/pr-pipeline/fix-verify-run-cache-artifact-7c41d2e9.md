---
bump: patch
---

### Fixed

- pr-merge's carried verdict reads stay warm again. Since the run cache moved to the `pr-merge-run-cache` artifact, only the `merge` job uploaded it, and its gate reads no lane verdict, so the chain started empty and stayed empty: every `enable-auto-merge` verifier read started cold, ran into the 4-minute read timeout, and left lane pull requests unarmed. A scheduled or hand-started `enable-auto-merge` job, whose reader is the only one that fills `run-record`, now keeps its reads the same way and uploads them as `pr-merge-verify-run-cache` (1-day retention), only when it kept a read. `carry-run-cache.mjs read` takes each artifact from the newest trusted run on main holding it and adds only the verify file's `carried-*` sections to the merge job's file, whose other sections, the skip refusals included, are unchanged; `carry()` still filters every entry, and a carried read still counts only toward a FAIL.
