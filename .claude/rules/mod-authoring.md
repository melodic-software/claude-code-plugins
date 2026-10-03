---
description: "Mods: before adding or changing a hooks module, load the built-in `plugin-authoring` skill and follow the mod-authoring convention, which points at the upstream mods pages and ADR 0049"
paths:
  - "plugins/*/hooks/**"
---

# Mod authoring

Mods: before adding `"modules"` to a plugin's `hooks/hooks.json` or changing a hooks module, load
the built-in `plugin-authoring` skill and read the
[mod-authoring convention](../../docs/conventions/mod-authoring/README.md). It points at the
upstream mods pages (as of Claude Code 2.1.288, rechecked on each pin bump) and lists the facts
they do not state, such as appending to the `context` a `tool.call` hook's `next` returned.
[ADR 0049](../../docs/adr/0049-adopt-claude-code-mods.md) records when to choose a mod and how it
is packaged.
