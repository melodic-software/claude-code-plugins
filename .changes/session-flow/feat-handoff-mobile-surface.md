---
bump: minor
---

The handoff prints a mobile form on the Claude mobile app: `save_point.py emit --format mobile` wraps the prompt's prose to fit a phone, keeps the path and session lines whole, and drops the terminal-only `claude --resume` note. Each surface's panel and checklist rules now live in the handoff's own `reference/surface/<surface>.md`, read only on that surface.
