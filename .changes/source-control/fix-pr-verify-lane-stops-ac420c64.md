---
bump: patch
---

### Changed

- The merge gate's verifier reader (`babysit_verify_evidence.py`) trusts the lanes App's spec text from before the pull request existed, as `resolve-pr.mjs` does: its filed issue body (a lower number than the pull request) or an edit before the pull request was created, and intake triage's refinement comment. `Reader.agent_identity` carries `merge.agent-identity`; with none set no App is trusted. Among several passes at the head, those of the newest run decide, so a pass judged again after a spec change replaces the stale one.
