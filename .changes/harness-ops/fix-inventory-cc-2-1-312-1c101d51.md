---
bump: patch
---

### Fixed

- **The inventory reads Claude Code 2.1.312 again.** The bundle tokenizer now reads a regex after a spread (`.../x/.test(y)`) and treats `of` as a name outside a for-of head (`${of/1000}`). Both shapes are new in 2.1.312 and left brace pairs spanning most of the bundle, so the `builtin_tools`, `builtin_plugins` and `bundled_workflows` canaries went missing and 19 bundled skills read as computed names. The slides skill now resolves through its helper `function h(t){...name:t.name...}` called once as `h(f)`, and a plugin gate written as a `function` declaration (`cc-plugin-easel`, `cc-plugin-claude-platform`) reports its flag. `cc-plugin-claude-platform`'s runtime-built `skills` getter is recorded as an accepted floor.
