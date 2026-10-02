---
description: "Before writing or changing a mod (a hooks module named by `modules` in `hooks.json`), load the built-in `plugin-authoring` skill and the upstream mods docs"
paths:
  - "plugins/*/hooks/**"
  - "plugins/*/types/**"
---

# Mod authoring

Before adding `"modules"` to a plugin's `hooks/hooks.json` or editing the hooks module it names,
load the built-in `plugin-authoring` skill and read the upstream mods pages for the parts you touch.
The [mod-authoring convention](../../docs/conventions/mod-authoring/README.md) covers when to use a
mod rather than a settings hook, packaging, and the version floor.
