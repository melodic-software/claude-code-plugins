---
bump: minor
---

### Added

- The Brief's Goal carries a fourth line, `Finish line: <merged | released | in use>, checked by <who> via <observable check>`, saying when the whole effort is done and who checks it. The interview proposes it in the restatement, the page export writes `- Finish line: not settled yet` when the restated goal has none, and `check-open-questions.sh --procedure --brief` fails a Goal whose Finish line is missing, empty or `not settled yet`. A Brief already in flight needs its Finish line added before Step 4. The `unattended_finish_check` setting names the check an unattended run puts in the default line.
