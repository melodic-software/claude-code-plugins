---
bump: patch
---

### Fixed

- Native auto-merge of a lanes App pull request now needs the verifier verdict pr-merge's gate needs. `enable-auto-merge.mjs` arms, and keeps armed, only with a pr-verify pass at the head it read, and disarms otherwise: an event run looks the head's pass up by exact artifact name, and the scheduled run asks the gate's reader, which also refuses a FAIL at the head and FAILs at `merge.max-verify-fails` or more heads. In the merge queue, `ci-status` requires a pass or pass-notes artifact at the queued head from a successful pr-verify run on main; a trusted approval of the head lifts it. Pull request events read no verdict, since pr-verify runs only after a green pull request run.
