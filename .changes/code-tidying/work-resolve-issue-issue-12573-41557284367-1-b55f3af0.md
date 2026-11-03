---
bump: patch
---

### Fixed

- The `/code-tidying:tidy` dependency-root and polyglot-services lane templates give `npx @biomejs/biome check` as the example lint command, not `npx biome check`, which runs an unrelated npm package when the project has no local Biome install (#12573).
