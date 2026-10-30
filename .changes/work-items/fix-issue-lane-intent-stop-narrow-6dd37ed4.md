---
bump: patch
---

### Fixed

- `/work-items:work` pushes back only on an intent question, adding `"cause": "intent"` to the
  outcome file. A choice of means or a design detail the issue leaves open is decided on evidence
  and built, with the choice and its basis in `summary`, instead of being sent to a person. A pushback reaches a person
  through `"cause": "intent"`, a reason that opens with a hold code, a host-run or attended code
  followed by a security risk, or the next intake round after a pushback whose reason, summary or
  cause names a security risk, whatever stops that round; a security mention alone first goes
  back through intake.
