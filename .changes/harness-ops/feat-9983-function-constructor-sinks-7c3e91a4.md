---
bump: patch
---

### Fixed

- The parser reader's sink rule no longer counts every use of the global `Function` as code built from a string. A `Function(...)` or `new Function(...)` whose result is discarded (an expression statement, or a sequence operand other than the last, as in `try{return new Function(""),!0}catch(e){return!1}`) builds code it never runs, so it is no sink. A direct call of one whose every argument is a constant string, such as lodash's `Function("return this")()`, has the code those strings spell parsed and scanned the same way, and is a sink only when that code is. Code holding an HTML-like comment (`<!--`, `-->`) is not folded. Every other use still counts, and a write of `Function` (`Function=g`, `globalThis.Function=g`, or a definer such as `Reflect.set` given `"Function"`) is now a sink of its own, since the folded calls trust it.
