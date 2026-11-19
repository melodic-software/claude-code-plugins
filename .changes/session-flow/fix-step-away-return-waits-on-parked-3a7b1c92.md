---
bump: patch
---

### Fixed

- wait for the person before acting on parked items after a return

  After the return report is shown and delivered, a parked Needs-you item,
  its recommended command included, now runs only once the person accepts
  it by naming it or through /session-flow:go-with-recommendations. Until
  then the session answers the person and waits, ending each answer with
  the open items and their recommendations so go-with-recommendations
  still finds them.
