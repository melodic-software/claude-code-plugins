---
bump: patch
---

### Added

- A resume-accuracy eval harness, `scripts/harness/resume_eval.py`, with seven synthetic `resume-eval` cases under `evals/re-*/`. It seeds a session, writes a handoff, a free-hand summary or a native `/compact`, then resumes it in a fresh Claude Code or Codex reader. It grades recall, artifact, continuation and decision probes and reports tokens on both sides in plugin eval's result schema, so `noise-report.py --baseline` compares any two arms. Directory-wide plugin-eval runs skip these cases.
