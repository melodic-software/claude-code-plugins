---
bump: patch
---

### Fixed

- `/harness-ops:inventory`'s parser reader counts a read of `constructor` as a Function-constructor sink: by name, by a computed key that may spell it, or as a destructured key. A computed key the scan cannot know, such as a parameter or a `for in` key, may spell it; such a read already counted as a load the scan cannot name. A loop counter's key does not. `(()=>1).constructor("code")()` and `({}).constructor.constructor("code")()` now make a trusted list read `partial`. A read that is only tested, compared with `===` or `!==`, or followed by `.name` stays clear.
