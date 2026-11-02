---
bump: patch
---

### Fixed

- `inventory.py --reader parser` no longer parses Bun's own `// @bun` bootstrap stub as a bundle module. When Bun's module table decodes, a `// @bun` run outside it is left out, and the binary source's `marker_runs_outside_graph` counts it. On Claude Code 2.1.316 that stub, with the runtime's string literals joined onto it, failed with `Unexpected token (4:7)` and made every name read as used. A module that does not parse still reads every name.
