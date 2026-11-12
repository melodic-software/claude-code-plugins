---
bump: major
---

### Removed

- The babysit scripts no longer read role labels from a repo-root `.work-item-tracker.json`. `babysit_tracker_binding.py` reads only the `tracker` mapping of `docs/conventions/work-items.yaml`; `LEGACY_PATH` is gone and `PATHS` holds only that file, so the merge-skip cache key no longer covers the JSON file. A repository bound only by the JSON file gets the default role labels. Fix: run `/work-items:setup apply`, which copies the binding into `docs/conventions/work-items.yaml`.

### Changed

- The babysit-loop skill, the babysit safety reference and the pull-request create reference no longer describe a JSON binding.
