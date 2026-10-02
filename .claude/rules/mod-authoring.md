---
description: "Mods stay deferred under ADR 0035: no plugin gains a `modules` key until its five go criteria pass; when they do, load the built-in `plugin-authoring` skill and the upstream mods docs first"
paths:
  - "plugins/*/hooks/**"
  - "plugins/*/types/**"
---

# Mod authoring

[ADR 0035](../../docs/adr/0035-defer-claude-code-mods-with-five-go-criteria.md) defers mods: do not
add `"modules"` to a plugin's `hooks/hooks.json` until all five of its go criteria pass. Once they
do, load the built-in `plugin-authoring` skill and the upstream mods pages before writing or
changing the hooks module, and follow the
[mod-authoring convention](../../docs/conventions/mod-authoring/README.md).
