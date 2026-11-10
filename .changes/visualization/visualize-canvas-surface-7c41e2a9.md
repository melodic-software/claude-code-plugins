---
bump: minor
---

### Added

- pick the diagram target by surface, and add the `hosted_canvas` setting

  `/visualization:visualize` draws locally in the Claude Code terminal
  (a Mermaid or ASCII fence, or a local page) even when a canvas server
  such as Excalidraw or tldraw is connected, and may draw on a connected
  canvas only on a surface that renders MCP Apps. A diagram that will be
  committed stays Mermaid. The new `hosted_canvas` setting (`allow`, the
  default, or `deny`) reads from `userConfig`,
  `docs/conventions/visualization.yaml` and the personal override;
  `deny` from any layer keeps diagram content off canvas servers reached
  over the network, and a local server stays allowed. The plugin ships
  no canvas server; the catalog points at the official Excalidraw and
  tldraw servers as optional user-level installs.
