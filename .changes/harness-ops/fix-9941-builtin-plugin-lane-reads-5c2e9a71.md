---
bump: patch
---

### Fixed

- **The inventory's built-in plugin lane no longer reports a wrong value where it cannot read one.** A method gate (`isAvailable(){...}`) now reads `gated: true` with `gate_flags` unresolved and named in `partial`, instead of `gated: false`. A plugin the loader requires at several call sites combines them: any unguarded site makes it `unconditional`, and sites guarded differently leave `load` partial instead of keeping the first site's guards. A command name registered twice with different records keeps both and leaves `commands` partial. A `hooks` object holding a spread, or a key the reader cannot see, lists the keys it read and names `classic_hooks` in `partial`.
