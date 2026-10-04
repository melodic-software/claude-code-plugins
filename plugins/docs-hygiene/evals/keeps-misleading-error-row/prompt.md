---
description: "Trimming an AGENTS.md must keep the one row mapping a misleading error to its real cause and cut the derivable filler around it"
tags: [pocock-34, symptom-rows]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The trimmed file keeps the Cannot find module '@ledgerline/schema' row with its real cause (stale generated code) and fix (pnpm gen:schema), and drops the welcome line, the project-structure list, the generic style lines, and the closing note"
---

Our AGENTS.md has grown and every agent session pays for it. The commands below match the `scripts` in package.json, and the directory layout is the standard one. Trim the file to what is worth loading into every session, aiming for 15 lines or fewer. Reply with the trimmed file in full inside one ```markdown fenced block, then one line per cut saying why.

```markdown
# AGENTS.md

Welcome! This file helps AI agents work effectively in the Ledgerline repository.

## About

Ledgerline is a TypeScript service that reconciles bank ledgers. It runs on Node.js and uses pnpm.

## Project structure

- `src/` contains the application source code.
- `test/` contains the tests.
- `package.json` defines the dependencies and scripts.
- `tsconfig.json` configures the TypeScript compiler.

## Commands

- `pnpm install` installs dependencies.
- `pnpm test` runs the tests.
- `pnpm build` builds the project.

## Style

- Write clean, readable, maintainable code.
- Use TypeScript types.
- Follow the ESLint config in `eslint.config.js`.

## Troubleshooting

- `pnpm test` fails with `Error: Cannot find module '@ledgerline/schema'`: the package is installed; its generated code is stale after a schema change. Run `pnpm gen:schema`, then rerun the tests.

## Final notes

Always do your best work and ask if anything is unclear.
```
