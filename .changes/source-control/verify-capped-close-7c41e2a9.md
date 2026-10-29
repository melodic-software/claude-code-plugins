---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` gains `capped_close` and a `capped-close` command. They close a
  lanes App pull request the verifier refuses for good (`VERIFY_FINAL`: `verify:repeated-fail`,
  `verify:too-old`) for a fresh attempt at its issue, with each FAILed head's findings from its
  `verdict.json`, or park the issue past `merge.verify-cap-attempts`. The gate calls it from
  `unattended_writes`. Neither refusal needs a person (`NEEDS_HUMAN` holds only
  `verify:untrusted-spec`). The cap's `verify:repeated-fail` detail now lists the FAILed heads.
- The cross-pull-request FAIL count leaves out a pull request the lanes App's capped-close record on
  the issue names. An unreadable sibling FAIL run refuses with the `SIBLING_UNREADABLE` detail.
