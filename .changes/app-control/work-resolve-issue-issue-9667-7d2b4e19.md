---
bump: patch
---

### Fixed

- `/app-control:drive` now keeps the per-run count of the control-skill contract's Sign-in floor, which the CLI cannot keep because it holds no count between calls. Drive calls `cli/ sign-in <account>` at most once per account in a run, unless committed config allows more. A failed sign-in ends every step that is not a finally step, and drive tries no other account in its place.
