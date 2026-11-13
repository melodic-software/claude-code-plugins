---
bump: patch
---

### Fixed

- `security-reviewer` no longer stops at its 30-turn cap with no report: it now has a turn budget (stop gathering by turn 22), opens its report with a `Criteria read:` line and closes it with a `Coverage:` line. With a findings path, it and `code-reviewer` write an early checkpoint ending `Coverage: in progress` to that path and replace it with the final report. Callers treat a partial-marked result, a missing file or a `Coverage: in progress` file as incomplete: `reviewer-handback.md` and quality-gate self and security modes resume the reviewer once and otherwise report a partial gate, and the fanout-sweep extractor keeps a checkpoint's findings and marks that surface incomplete.
