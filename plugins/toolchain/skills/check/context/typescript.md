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

### Test output signals

Read for the `Passed on retry` and `Run signals to echo` rules in `SKILL.md` §2:

- **Retry-earned pass (Playwright Test).** With `retries` set, Playwright sorts results into passed, flaky (failed first, passed on retry) and failed, and its summary carries a `flaky` count with the test names. That count is the `pass (flaky: N)` value. Pointer: <https://playwright.dev/docs/test-retries>. As of: 2026-10-06 (Playwright 1.63). Recheck trigger: a release renames the outcome or changes the summary.
- **Other runners.** When the project config sets retries (Jest `retryTimes`, Vitest `retry`) and the output does not separate a retried pass, say `retries configured, flaky count not reported` rather than a clean pass.
- **Slowest tests and seed.** Echo a slow-test or seed line only when the runner prints one; neither is added to the command.

## Lint

```bash
# Use the project's configured linter — biome.json → Biome; eslint config → ESLint
cd "$PROJECT_DIR" && npx biome check .

# Format-only (/toolchain:lint --fix)
cd "$PROJECT_DIR" && npx biome format --write <files>

# Code-fix (lint autofixes — /toolchain:lint --code-fix only)
cd "$PROJECT_DIR" && npx biome check --write <files>
```

## Gotchas

- **Run from project directory**: each `package.json` defines an independent project root
- **Biome walks up** to find `biome.json` from the CWD, so run from project dir, not repo root
- **`tsc --noEmit`** belongs in CI and `/toolchain:check`, not in edit-time hooks: tsc is project-scoped and takes seconds

## Project discovery

Find all TypeScript/JS projects dynamically:

```bash
find "$REPO_ROOT" -name "package.json" -not -path "*/node_modules/*" -not -path "*/.venv/*"
```
