---
bump: patch
---

### Fixed

- "Check the probe" in the PR capture, and the subprocess scrub probe in `upstream-apply-changelog.yml`, now say the fence was not tested when the probe session made no Read call on a fenced path, instead of reporting the file tools as unfenced. `capture-probe.mjs reads` exits 3 for that case. Both still fail the job, and any Read that came back or got no answer is still reported as an open fence.
