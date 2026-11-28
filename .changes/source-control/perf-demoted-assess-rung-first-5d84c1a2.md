---
bump: patch
---

### Changed

- The babysit-prs unattended merge gate refuses a pull request with `rung-off:<input>` as soon as it reads the effective rung as off, before the in-flight, eligibility and verify-evidence reads, so a demoted lane's scheduled sweep no longer reads each candidate's evidence; the refusal, blockers, queue writes and AI-review re-runs are unchanged, and a Dependabot pull request still has its class read for the dependency hold.
