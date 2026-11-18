---
bump: minor
---

### Added

- `diagram_target` gains `excalidraw-file`: `/visualization:visualize` writes a flow, flowchart, state diagram or swim lane (one labeled frame per lane) as `docs/diagrams/<name>.excalidraw` at the repository root, to open and edit in an Excalidraw editor. It needs no canvas server and no network, works in the Claude Code terminal, asks before replacing an existing file, never stages or commits the file, and reports its absolute path. A resolved `medium` does not override it; a medium argument, a form the person names, or a calling skill that needs the diagram inline does. Outside a repository it falls back to `auto`.
- `lib/diagram-file-check.mjs` checks a drafted `.excalidraw` file's structure before it is written: the file marker, a numeric version, elements of the drawn types with ids, positions and sizes, references that resolve, and no link, image or embed.
