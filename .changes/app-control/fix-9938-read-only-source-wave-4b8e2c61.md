---
bump: patch
---

### Added

- The `app-control:source-reader` agent, whose tool list holds Read, Grep and Glob only, for the `/app-control:map refresh` source wave.

### Fixed

- `/app-control:map refresh` sends its source wave through `app-control:source-reader`, so a subagent reading app source can no longer edit, write or run anything; before, the read-only limit was only an instruction in its prompt. When the agent does not resolve, the pass is blocked rather than sent through another agent. Each prompt now opens with the untrusted-content framing and quotes every repository value inside the item-content-trust fence. The working-tree tripwire is named a backstop, and the report states what it cannot see: writes under `.git/`, to ignored paths and outside the checkout.
