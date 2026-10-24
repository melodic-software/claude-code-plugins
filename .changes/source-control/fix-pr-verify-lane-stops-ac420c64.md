---
bump: patch
---

### Changed

- The merge gate's verifier reader (`babysit_verify_evidence.py`) trusts the lanes App's spec text from before the pull request existed, as `resolve-pr.mjs` does: an issue it filed with a lower number than the pull request, edited since only by a trusted human, and intake triage's refinement comment from before the pull request was created. `Reader.agent_identity` carries `merge.agent-identity`; with none set (the `evidence` command without `--base-sha`) no App is trusted. Among several passes at the head, those of the newest run decide, so a pass judged again after a spec change replaces the stale one.
