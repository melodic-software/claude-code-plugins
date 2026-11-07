---
bump: patch
---

### Fixed

- `/verification:confirm` keeps a fresh-context verifier's verdict final ([#14045](https://github.com/melodic-software/claude-code-plugins/issues/14045)):
  - The verdict is recorded and published as the verifier returned it. When it comes back with an open question or a scope doubt, the producing session never answers it and never upgrades the verdict; it fixes what the verdict names, or dispatches a new fresh verifier whose brief adds only facts, with no wanted verdict and none of the earlier verifiers' recommendations.
  - The report (a new `Verifier verdicts:` line) and the manifest list every verdict returned on the head beside the final one, and the evidence loop appends each one to `heads`.
  - New eval case `confirm-verifier-needs-work-not-upgraded`: a NEEDS WORK verdict recommending acceptance is not recorded as CONFIRMED.
