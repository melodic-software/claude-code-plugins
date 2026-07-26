# Gotchas — `/discovery:research`

Failure modes observed in real runs of this skill. Each is a way a run can look finished and be
wrong, which is why none of them is caught by "did I do a good job?" — they are caught by the
outcome gate's artifact-grounded criteria, or not at all.

- **A silent preload miss looks exactly like a good run.** A dispatched agent whose `skills:` entry
  did not resolve starts anyway, writes an artifact, and reports `coverage: complete`; the harness
  logs a warning to the debug log and nowhere else. The `preload_token` echo is the only seam that
  distinguishes the two, which is why a missing or mismatched token discards the run rather than
  downgrading it.
- **Enumerating the corpus from search results.** A Phase 0 ledger built from what searching happened
  to surface inherits precisely the blind spot the ledger exists to close, and then certifies it. Use
  a surface that is exhaustive by construction, and record the corpus as narrowed when it is.
- **Stopping at the floor while gaps remain.** Every query minimum reads "at least", never "exactly".
  Models satisfice to stated numbers, so a flat floor reliably produces exactly-floor shallow phases;
  the Phase 1 gap count is what sets the Phase 2 query count.
- **A probe standing in for a fetch.** A title, an index entry, or a search snippet establishes that
  a rung *exists* — never that it lacks the claim, because the section being chased is exactly what a
  snippet omits. Criterion 9 grades the fetch.
- **Treating a curated index as exhaustive.** `llms.txt` is a maintainer hand-pick and deliberately
  partial. A miss there is silence, not evidence of absence — for a rung, for a page, or for a corpus
  item.
- **Self-grading the verifier rows.** Criteria 4 and 7 ask the run to judge the quality of its own
  choices. They belong to a fresh context whatever the execution posture: a dispatched run returns
  `verification: pending`, and an inline run hands them off rather than answering them.
- **Reading the coverage ledger instead of running the gate.** A model cannot reliably audit its own
  checklist, and the context most motivated to call it finished is the one reading it. Criterion 11
  cites the script's exit status; exit 2 — a ledger the script could not parse — is a FAIL, never a
  pass.
- **Accepting the answer that arrives first.** The falsification query exists because a run that only
  looks for confirmation finds it. Phase 2 without it is confirmation bias with a citation list.
- **Layering research after a mid-task pivot.** A superseded section outlives the approach it
  described and misleads the planning step into planning against a direction already abandoned.
  Delete it and re-run; do not keep both.
