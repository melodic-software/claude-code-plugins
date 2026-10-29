---
bump: minor
---

### Added

- **The parser reader's sink rule clears Bun's runtime helpers when they define only on fresh objects.** Under `--reader=parser`, `Object.create(...)`, an object an `Object` definer returns, `new` of a class the module declares, a `?:` of fresh objects, and a parameter assigned one before any read now count as fresh targets. So does `this` in a function only ever bound to a fresh object (`r.bind(b,c)`), and a parameter of a function every caller passes a fresh object. For an exported helper such as `__export`, every importer's call must pass one, no module may re-export the helper, and no module may load the runtime module whole or load a file the parser cannot name. A target cleared through `Object.create` or a definer's return makes `Object` and `create` or the definer's name trusted names, and one cleared through `bind` makes `bind` one; every module is then checked for those names too. Like `Function`, `Object` passed as a string counts only when the callee is a definer. A declarator destructuring definers from `Object` (`var{defineProperty:f}=Object`) is no longer a definer escape when each definer it takes is only ever called and every other key is an inert static such as `getPrototypeOf`; each call is checked like a direct `Object.defineProperty` call. A parameter of a function that reads `arguments` or is declared in a block is never followed, since sloppy code can change or call it unseen.

### Fixed

- Under `--reader=parser`, code a `Function("...")()` call folds to is a sink when it loads a file (`import("...")`, `require("...")`), since the load scan never reads it and such a load could take a module whole.
