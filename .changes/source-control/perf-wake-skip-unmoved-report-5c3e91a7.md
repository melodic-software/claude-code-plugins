---
bump: patch
---

### Changed

- `babysit_verify_evidence.py refusal-stands` says whether an earlier tick's post-merge report refuses on what it found (exit 1, or needs-dispatch, unattributed, quarantines or excused; not its age, a re-run or a failed read) while nothing it was read from has moved: main's tip, the config commit, the demotion, the quarantine issues, the pins, and every verifying run, including one created, re-run or still running since. pr-merge's PR-scoped wake then refuses as that report does without running the post-merge check again.
