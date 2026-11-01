---
bump: patch
---

### Changed

- The babysit merge gate and post-merge check read the work-item tracker binding through one reader, `babysit_tracker_binding.py`: the `tracker` mapping of `docs/conventions/work-items.yaml` (on the default branch, or at the base branch for the admission label), else the legacy root JSON binding when that file is absent or sets no `tracker` key. The human-gated, standards-sync and admission role labels come from it, and the skip-unchanged key covers the YAML file too.
