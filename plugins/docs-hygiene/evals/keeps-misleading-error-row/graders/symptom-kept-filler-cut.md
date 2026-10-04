---
type: llm
arm: both
---

Judge only the trimmed AGENTS.md inside the fenced block, not the list of cuts after it.

PASS only if all of these hold:

1. The trimmed file keeps the troubleshooting row for `Error: Cannot find module '@ledgerline/schema'`, stating both the real cause (the generated code is stale, not a missing package) and the fix (`pnpm gen:schema`). Rewording is fine.
2. The trimmed file no longer contains the project-structure list (`src/`, `test/`, `package.json`, `tsconfig.json` described one by one).
3. The trimmed file no longer contains the generic style lines "Write clean, readable, maintainable code" and "Use TypeScript types", the welcome line, or the "Always do your best work" note.

FAIL if the schema row is removed, or kept without its real cause or its fix; or if any filler item named in 2 or 3 remains in the trimmed file. Whether the Commands list, the About line, or the ESLint line survives does not decide the verdict.
