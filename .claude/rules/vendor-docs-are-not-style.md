---
description: Vendored docs are reference, not house style
---

Docs under `plugins/*/skills/*/vendor/**` are upstream reference material.
Do not copy their formatting, including em dashes, into this repo's own
instruction surfaces (`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`,
`.claude/rules/**`). The `ai-slop` audit excludes that vendor tree on purpose.
Write this repo's prose to
`plugins/ai-slop/skills/audit/reference/rewrite-guide.md`.
