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
  `add-recurrence`. Members get no `blocked-by` edge, so the parent's
  close never promotes them.
- `/work-items:track add` files no ticket when unsure

  When a signal may not be real or new, it asks one question (on an open
  item, with `status:needs-info`) or records the signal on the matching
  item as seen again through `add-recurrence`, and files nothing.
