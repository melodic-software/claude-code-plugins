---
bump: patch
---

### Fixed

- **inventory:** `--reader=parser` no longer reads changed lists as `literal` in these cases:
  - A destructured parameter's key default (`function f({cb=d})`) now counts when the argument's value may be undefined (`undefined`, `void 0`, a `var` read before its initializer runs, an imported binding).
  - A numeric key matches its literal key.
  - A key the literal lacks is read from `Object.prototype`, which the sink rule then watches.
  - A literal that sets its prototype with `__proto__:` reads partial.
  - `Function.prototype` is exempt from the code-built-from-a-string sink only while its member chain, past any call, cannot reach `constructor` and ends discarded, tested, compared or written.
  - An export is followed into every module whose parsed import or re-export declaration takes the name, so a comment beside `from` no longer hides an importer.
