---
bump: patch
---

### Fixed

- **A test name holding an escaped quote is no longer cut at it.** The scanner's `--blocks` names, which the test judge hands the judge and matches its verdicts by, kept only the text before a PowerShell `''`, `` `" `` or `""`, or a backslash-escaped quote elsewhere, so a verdict the judge gave under the test's full name matched no block and the run counted as "judge exited 0 with no usable result".
- **The test judge keeps the output of a run that gave no usable result.** It is saved beside the ledger as `unusable-<time>-<pid>.txt` (pruned after 7 days with the rest), and the judge log quotes the start of the judge's result and stderr, with control characters removed, so the failure can be diagnosed.
- **A file the session wrote that no longer exists is logged once.** Its session records are dropped on the first skip, so later Stops neither re-check nor re-log it; a write that brings the file back records it again.
