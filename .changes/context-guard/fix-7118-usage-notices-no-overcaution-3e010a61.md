---
bump: minor
---

### Changed

- Past `smart`, the zone lines Claude reads are now followed by one options line: record decisions and pending items in a durable file, then continue, `/compact`, or hand off with `/session-flow:handoff`, as Claude and the user choose. The line also says a zone never calls for terser output, fewer agents, or lower quality (#7118).
