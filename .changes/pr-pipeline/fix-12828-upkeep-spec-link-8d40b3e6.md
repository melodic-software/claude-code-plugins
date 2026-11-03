---
bump: patch
---

### Fixed

- Each code-tidying upkeep pull request's body opens with `Refs: #<upkeep_spec_issue>`, the standing
  spec issue named in `docs/conventions/code-tidying.yaml`, in place of `No related issue`, so
  pr-verify judges the pull request against that spec instead of failing it for having none. The
  batch adds the line itself and refuses a body that links another issue. With the setting missing
  or invalid the gate fails before the model runs and the batch opens no pull request.
