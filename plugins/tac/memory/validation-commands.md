# Validation Commands

Patterns for adding validation commands to plans and workflows.

## The Validation Commands Section

Every plan should include a validation section:

```markdown
## Validation Commands

Execute every command to validate with 100% confidence and zero regressions

- [lint command]
- [type check command]
- [unit test command]
- [build command]
- [e2e test if applicable]
```markdown

## Why This Matters

Without explicit validation commands:

- Agents "complete" tasks without verification
- Errors accumulate silently
- Manual review required for every change

With validation commands:

- Automated verification of every change
- Immediate feedback on failures
- Self-documenting success criteria

## Standard Template

```markdown
## Validation Commands

Execute every command to validate with 100% confidence and zero regressions

- `[lint command]` - Code style and syntax
- `[type check command]` - Type safety
- `[test command]` - Behavior correctness
- `[build command]` - Production readiness
```markdown

## By Technology Stack

### Python (uv + pytest)

```markdown
## Validation Commands

- `cd app && uv run ruff check .` - Linting
- `cd app && uv run mypy .` - Type checking
- `cd app && uv run pytest -v` - Tests
```markdown

### Python (pip + pytest)

```markdown
## Validation Commands

- `flake8 .` - Linting
- `mypy .` - Type checking
- `pytest -v` - Tests
```markdown

### TypeScript (Node.js)

```markdown
## Validation Commands

- `npm run lint` - ESLint
- `npm run typecheck` or `npx tsc --noEmit` - Type checking
- `npm test` - Tests
- `npm run build` - Build verification
```markdown

### TypeScript (Bun)

```markdown
## Validation Commands

- `bun run lint` - Linting
- `bun tsc --noEmit` - Type checking
- `bun test` - Tests
- `bun run build` - Build verification
```markdown

### Go

```markdown
## Validation Commands

- `go fmt ./...` - Formatting
- `go vet ./...` - Static analysis
- `go test ./... -v` - Tests
- `go build ./...` - Build verification
```markdown

### Rust

```markdown
## Validation Commands

- `cargo fmt --check` - Formatting
- `cargo clippy` - Linting
- `cargo test` - Tests
- `cargo build --release` - Build verification
```bash

## Discovering Validation Commands

When working with an unfamiliar project:

1. **Check package.json** (Node.js):

   ```bash
   cat package.json | grep -A 20 '"scripts"'
   ```

1. **Check pyproject.toml** (Python):

   ```bash
   cat pyproject.toml | grep -A 20 '\[tool'
   ```

2. **Check Makefile**:

   ```bash
   cat Makefile | grep -E '^[a-z]+:'
   ```

3. **Check README** for development section

4. **Check CI/CD** (.github/workflows/):

   ```bash
   cat .github/workflows/*.yml | grep -E 'run:'
   ```

## E2E Validation (When Applicable)

For features with user-facing changes:

```markdown
## Validation Commands

[...standard commands...]

### E2E Validation

If E2E test exists for this feature:
Read `.claude/commands/test-e2e.md`, then execute the relevant E2E test spec
```markdown

## Validation Order

Run commands in order of speed (fast failures first):

1. **Lint** (seconds) - Catch syntax/style issues
2. **Type Check** (seconds) - Catch type errors
3. **Unit Tests** (seconds) - Catch logic errors
4. **Build** (seconds-minutes) - Catch compilation errors
5. **Integration Tests** (minutes) - Catch interaction errors
6. **E2E Tests** (minutes) - Catch user flow errors

## Related

- @closed-loop-anatomy.md - The full Request-Validate-Resolve structure
- @test-leverage-point.md - Why tests are the ultimate validation
- @e2e-test-patterns.md - E2E testing patterns
