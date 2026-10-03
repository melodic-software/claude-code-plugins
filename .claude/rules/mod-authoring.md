---
description: "A mod follows ADR 0046's five scope rules; before adding or changing a hooks module, load the built-in `plugin-authoring` skill and follow the mod-authoring convention"
paths:
  - "plugins/*/hooks/**"
---

# Mod authoring

A mod in this repository follows the five scope rules in
[ADR 0046](../../docs/adr/0046-adopt-claude-code-mods-within-five-scope-rules.md#scope-rules).
Before adding `"modules"` to a plugin's `hooks/hooks.json` or changing a hooks module, load the
built-in `plugin-authoring` skill and follow the
[mod-authoring convention](../../docs/conventions/mod-authoring/README.md).
