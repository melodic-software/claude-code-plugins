---
bump: patch
---

### Fixed

- **The parser reader's flow check trusts the engine's implicit lookups.** A spread of the array now trusts `@@iterator` and `next`; `slice`, `map`, `filter`, `concat`, `flat` and `flatMap` trust `constructor` and `@@species`, and `concat` trusts `@@isConcatSpreadable`; a member read used as a value trusts its key (the array's own `length` and literal elements excepted), and one whose computed key names nothing is no longer followed. A spread or value-only read of the array now reaches the sink check even when nothing mutates it, so a module patching any of those names reads the list `partial` under `--reader=parser` instead of a wrong `literal`. Fail-closed: a bundle that may write `Symbol.iterator` or `next` on an object the sink rule cannot show is no prototype (2.1.287's yallist writes `Symbol.iterator` on one) now reads every spread-built list `partial` under the parser.
