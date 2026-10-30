---
bump: patch
---

### Fixed

- `/work-items:work` pushes back only on an intent question, adding `"cause": "intent"` to the
  outcome file. A choice of means or a design detail the issue leaves open is decided on evidence
  and built, with the choice and its basis in `summary`, instead of being sent to a person. A pushback reaches a person
  through `"cause": "intent"`, a reason or cause that opens with a hold code, a host-run or
  attended code followed by a security risk, or a spent intake round whose reason, summary,
  not-done item or cause names a security risk again; a security mention alone first goes back
  through intake.
