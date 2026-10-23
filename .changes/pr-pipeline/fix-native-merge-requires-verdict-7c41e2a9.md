---
bump: patch
---

### Fixed

- Native auto-merge of a lanes App pull request now needs the verifier verdict pr-merge's gate needs. `enable-auto-merge.mjs` arms, and keeps armed, only when pr-merge's gate reader refuses nothing at the head it read (a pr-verify pass, no FAIL at the head, FAILs under `merge.max-verify-fails`, an unchanged trusted spec), and only on its scheduled or hand-started run; event runs never arm. `ci-status` turns an armed lanes App pull request's auto-merge off on each push to its head. In the merge queue, `ci-status` requires a pass or pass-notes artifact at the queued head from a successful pr-verify run on main; a trusted approval of the head lifts it. Pull request events read no verdict, since pr-verify runs only after a green pull request run.
