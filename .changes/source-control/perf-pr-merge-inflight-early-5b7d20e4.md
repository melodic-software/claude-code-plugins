---
bump: patch
---

### Changed

- The unattended merge policy stops judging a pull request once the in-flight rule refuses it and it has no merge-queue entry of its own: the eligibility, promotion, risk-evidence, changed-files and verifier-verdict reads are skipped, and the refusal reads `in-flight:<reason>` as before. A pull request that is itself queued, a Dependabot pull request, or one whose queue read was not whole is still judged in full, so its own entry still leaves the queue on its own refusal. Its risk comment and verifier escalation wait for a run with no lane merge in flight. The merge-queue sweep runs in every gate process as before.
