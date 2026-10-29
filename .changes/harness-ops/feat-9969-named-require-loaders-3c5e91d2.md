---
bump: minor
---

### Added

- **The parser reader follows an exported `require` alias into its importers.** Bun's runtime chunk exports `import.meta.require` (`var Fe=import.meta.require;export{...,Fe}`), and other modules load files through the imported `Fe("...")`. Under `--reader=parser` such an alias is now a named loader: an importer's call of it with a literal specifier loads that file, followed like `require(...)`. Any other use (a call with no literal, an alias, an escape, a re-export) still counts as a load the parser cannot name, in the sink rule too. The alias stays unknown when Bun's module table names no file for its module, or when a module loads that file whole.
- A `.require` member read that is only tested for truth no longer counts as a load the parser cannot name: a `&&` operand other than the last, an `if`, loop or `?:` test, or a `!` operand, as in lodash's `w&&w.require&&w.require("util")`. A read that may pass the loader on still counts: the last `&&` operand, or any `||` or `??` operand.
