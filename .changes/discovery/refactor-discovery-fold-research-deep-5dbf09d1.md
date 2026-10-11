---
bump: minor
---

### Removed

- **BREAKING: `/discovery:research-deep` is retired.** Its multi-topic split, its `discovery:research-sweep` workflow tier and its post-dispatch verification are now the deep tier of `/discovery:research`. Run `/discovery:research deep <topic>`, or ask for several topics at once; the main conversation picks the tier before dispatching, and a dispatched or forked run never takes it. The research-deep eval cases moved into the research skill's evals.

### Changed

- **`/discovery:research` carries the deep-research triggers and a `deep` argument.** Its description adds the trigger phrases research-deep owned, and it grants only the `discovery:research-sweep` workflow launch. The deep-tier procedure loads from `skills/research/context/deep-tier.md`, so a dispatched researcher does not preload it.
