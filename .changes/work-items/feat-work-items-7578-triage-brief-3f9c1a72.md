---
bump: minor
---

### Added

- triage clusters intake that shares a signature under one parent

  Items with the same error text or failing check, the same reproduced
  symptom, or the same suspect commit form one cluster. The parent (the
  oldest member with a confirmed reproduction, else the oldest) is the
  only member that can get `agent-ready`; every other member closes as a
  duplicate, with its sighting recorded on the parent through
  `add-recurrence` (a body note for a local-markdown member, whose
  `file://` link `add-recurrence` refuses). Members get no `blocked-by`
  edge, so the parent's close never promotes them.
- `/work-items:track add` files no ticket when unsure

  Unless `--force` is passed or the user chose "Add anyway", a signal
  that may not be real or new gets one question first (on an open item,
  with `status:needs-info`). An answer showing it is real and new files
  it; otherwise the signal is recorded on the matching item as seen
  again and nothing is filed.
