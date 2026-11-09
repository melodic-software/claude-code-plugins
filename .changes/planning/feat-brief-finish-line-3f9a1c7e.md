---
bump: minor
---

### Added

- The Brief's Goal carries a fourth line, `Finish line: <merged | released | in use>, checked by <who> via <observable check>`, saying when the whole effort is done and who checks it. The interview proposes it in the restatement, the page export writes `- Finish line: not settled yet` when the restated goal has none, and `check-open-questions.sh --procedure --brief` fails a Goal whose Finish line is missing, empty or `not settled yet`. A Brief already in flight needs its Finish line added before Step 4. The `unattended_finish_check` setting names the check an unattended run puts in the default line.
- A stated problem whose evidence is only `reported` gets one instance question (the last concrete instance, what it cost, who hit it), never a why chain and never a question reopening the named solution; a problem with `observed` evidence gets none, and the restatement names the artifact. A Problem field that would read `unknown` gets candidate values from the repository and the conversation to confirm or correct; a confirmed value is rated `reported`.
- Unattended, the interview skips the instance question and the candidates and fills the Goal with `Finish line: merged, checked by <check> via the pull request's checks (filled automatically: unattended)`. It stops for a human, with a `blocked` USER-RESERVED row and a `Stopped: needs a human: <reason>` line, only when the item contradicts a recorded Intent or Vision or raises a critical security issue.
