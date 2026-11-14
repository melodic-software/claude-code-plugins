---
bump: patch
---

### Changed

- `/planning:plan` flags change amplification at plan time: when the files-affected list shows one
  logical change spread over many sites, the plan says so and proposes moving the repeated
  knowledge behind one module first, or records why not.
