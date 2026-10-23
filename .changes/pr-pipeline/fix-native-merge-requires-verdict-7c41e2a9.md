---
bump: patch
---

### Fixed

- Native auto-merge of a lanes App pull request now needs the verifier verdict pr-merge's gate needs. `enable-auto-merge.mjs` arms, and keeps armed, only when the gate's reader refuses nothing at the head it read (a pr-verify pass stands, no FAIL at the head, FAILs under `merge.max-verify-fails`), and disarms otherwise. In the merge queue, `ci-status` requires a pass or pass-notes artifact at the queued head from a successful pr-verify run on main; a trusted approval of the head lifts it. Pull request events read no verdict, since pr-verify runs only after a green pull request run.
