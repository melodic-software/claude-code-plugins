---
description: "Vendored upstream docs are reference content, not this repository's house style; read before imitating anything under a skill's vendor/ tree"
paths:
  - "plugins/*/skills/*/vendor/**"
---

# Vendored docs are reference, not house style

Files under `plugins/*/skills/*/vendor/**` are upstream material, copied verbatim and refreshed
by each pack's update script. Read them for what they say, never for how they say it. When prose
you write for this repository (a `SKILL.md`, a plugin README, `AGENTS.md`, `.claude/rules/**`)
draws on a vendored file, restate the content in the house style and leave the vendor's
formatting behind, em dashes included.

The vendor tree is excluded from the `ai-slop` audit (`.claude/ai-slop.json`) and from the
spell-check lane because nothing there is authored here, not because its style is approved. Check
authored prose with `/ai-slop:audit`, and apply that skill's rewrite discipline with
`/ai-slop:audit fix`.
