# TypeScript Build Commands

## Build / Compile

```bash
cd "$PROJECT_DIR" && npx tsc --noEmit
```

## Test

```bash
# Use the project's configured runner — check package.json scripts first
cd "$PROJECT_DIR" && npm test
# or directly: npx vitest run / npx jest
```

## Lint

```bash
# Use the project's configured linter — biome.json → Biome; eslint config → ESLint
cd "$PROJECT_DIR" && npx biome check .

# Auto-fix
cd "$PROJECT_DIR" && npx biome check --write .
```

## Gotchas

- **Run from project directory** — each `package.json` defines an independent project root
- **Biome walks up** to find `biome.json` from the CWD — run from project dir, not repo root
- **`tsc --noEmit`** belongs in CI and `/build`, not in edit-time hooks — tsc is project-scoped and takes seconds
- **npx on Windows** — programs spawning bare `npx` fail because `npx` is a `.cmd` file; CLI usage via a shell works fine

## Project discovery

Find all TypeScript/JS projects dynamically:

```bash
find "$REPO_ROOT" -name "package.json" -not -path "*/node_modules/*" -not -path "*/.venv/*"
```
