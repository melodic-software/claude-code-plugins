---
bump: patch
---

### Fixed

- `/testing:audit` `rule-source-text-read` now catches a JS/TS test that reads a source file through a same-file `const` path (a literal, or a `join`/`resolve` over literals, even across lines), and a route file name with a `$` segment such as `_app.pitches.$pitchId.tsx`. The rule stays report-only.
- `/testing:write` no longer says constants are covered by drift guard tests in consumers: a drift guard compares the constant to its external source of truth, never to a literal copied from the code.
