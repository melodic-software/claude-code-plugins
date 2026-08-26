---
description: Vendored docs are reference, not house style
---

Docs under `plugins/*/skills/*/vendor/**` are upstream reference material.
Do not copy their formatting, including em dashes, into this repo's own
instruction surfaces (`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`,
`.claude/rules/**`). The `ai-slop` audit excludes that vendor tree on purpose.
Write this repo's prose to the house style the `ai-slop:audit` skill owns;
run `/ai-slop:audit` to check a file against it, and `/ai-slop:audit fix` to
apply that skill's rewrite discipline.
