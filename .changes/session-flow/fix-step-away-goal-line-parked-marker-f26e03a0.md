---
bump: patch
---

### Fixed

- name the parked marker in the step-away goal line

  away.py counts an unticked task item closed when its text matches
  \bparked\b. The /goal evaluator refused to accept that as "marked
  parked" while away.py check exited 0, so the goal line and the
  continue-in-background done condition now name the marker the script
  reads: ticked done or, when unticked, the word "parked" in its text.
