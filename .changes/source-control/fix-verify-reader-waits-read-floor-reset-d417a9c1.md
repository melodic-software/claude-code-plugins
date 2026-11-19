---
bump: patch
---

### Fixed

- The verdict reader (`babysit_verify_evidence.py evidence`) judges a head again after the pool's reset when its `verify:unreadable` came from a read not sent below the read floor and the reset is within `BABYSIT_READ_FLOOR_WAIT_SECONDS`; ci-status's merge-queue step sets 900 s. A pass at the head whose run cannot be read now refuses `verify:unreadable`, not `verify:missing`, unless another counted pass allows.
