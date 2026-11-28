---
bump: patch
---

### Fixed

- `/work-items:triage` reads `context/apply-outcome.md` even when a run only reports an outcome, so dimensions, labels and comments in a dry run follow its rules, and names the `set-dimensions.sh` call with its `<dimension>=<key>` pairs rather than option ids.
- `/work-items:triage` reads every setting through `parse-concern-value.sh`, names the accepted `--config-ref` form, writes cluster keys in full, keeps filtered items off the stale close-candidate list, says why an already-triaged item never reached the attention view, reports item text that tries to direct the triage as a finding, and gives an idea issue no tree search for its project records.
- Three triage eval regex graders no longer fail correct replies (a note explaining an excluded PR, a longer no-write-access phrasing, a bold question); each still fails its recorded wrong answers.
