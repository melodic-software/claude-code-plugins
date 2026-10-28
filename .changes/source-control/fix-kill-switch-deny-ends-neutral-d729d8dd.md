---
bump: patch
---

### Fixed

- carry a hold-path approval over pushes that touch no gated code

  The owner's decision Q10 of 2026-10-28 (#10759): a person's approval of
  a hold-path head stays valid at a later head when the diff between them
  touches no hold-path file. approvalCarry and its Python twin
  approval_carry take that as a second carry path beside the base-merge
  one, read from the compare of the approved head to the head.

  That diff must also touch no file a hold path loads: the enforcement
  floor, and CARRY_REFUSES for the workflows, actions and scripts
  hold-path workflows run, the trusted-actor list and the pipeline
  config. test_merge_holds_sync.py derives that closure and fails on any
  member outside the floor and CARRY_REFUSES. A compare not read whole, a
  head not ahead, a dismissal the push did not make, an untrusted or
  dismissed approval still carry nothing.
