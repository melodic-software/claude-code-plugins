---
bump: minor
---

### Added

- `diagram_target` setting for `/visualization:visualize`: `auto` (default, pick by surface), `terminal`, `local-page`, `excalidraw` or `tldraw`. It is read from the `userConfig` option, the team file `docs/conventions/visualization.yaml` and the personal override `docs/conventions/visualization.local.yaml`, a later layer winning, and applies only when the form is a diagram. A target that is unavailable (no such server connected, a surface that does not render it, or `hosted_canvas` forbids it) falls back to `auto` with a one-line notice. New eval case `viz-diagram-target-fallback`.
- README: `hosted_canvas` steers only this skill; a Claude Code permission deny rule on the server's tools, such as `mcp__tldraw__*`, blocks the server for every tool.
