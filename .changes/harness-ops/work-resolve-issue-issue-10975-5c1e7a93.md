---
bump: patch
---

### Fixed

- `/harness-ops:inventory`'s parser reader counts a read of `constructor` as a Function-constructor sink: by name, by a computed key that may spell it, or as a destructured key. `(()=>1).constructor("code")()` and `({}).constructor.constructor("code")()` now make a trusted list read `partial`. A read that is only tested, compared with `===` or `!==`, or followed by `.name` stays clear.
