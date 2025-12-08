# Tests as Leverage Point

Tests are the #1 leverage point for feedback loops in agentic systems.

## Why Tests?

Tests provide the ideal validation mechanism:

| Property | Why It Matters |
| ---------- | --------------- |
| **Deterministic** | Same input = same output, no ambiguity |
| **Fast** | Milliseconds to seconds, not minutes |
| **Automatable** | No human in the loop required |
| **Structured Output** | Pass/fail + error messages for parsing |
| **Reproducible** | Can re-run identical validation |

## Test Types as Validation Mechanisms

### Unit Tests

**Scope**: Single function or method
**Speed**: Milliseconds
**Best For**: Core logic validation

```bash
pytest tests/unit/ -v
```markdown

### Integration Tests

**Scope**: Component interactions
**Speed**: Seconds
**Best For**: API contracts, database operations

```bash
pytest tests/integration/ -v
```markdown

### E2E Tests

**Scope**: Full user journeys
**Speed**: Seconds to minutes
**Best For**: Critical paths, user flows

```bash
playwright test
```markdown

## The Test Leverage Point Pattern

When designing agentic workflows:

```text
1. What could go wrong?
   → Write a test that catches it

2. How do I know it worked?
   → Write a test that proves it

3. How do I prevent regression?
   → Write a test that guards it
```markdown

## Test Output as Structured Data

Transform test results into actionable data:

```json
{
  "test_name": "test_user_login",
  "passed": false,
  "execution_command": "pytest tests/test_auth.py::test_user_login -v",
  "test_purpose": "Verify user can log in with valid credentials",
  "error": "AssertionError: Expected status 200, got 401"
}
```markdown

This structure enables:

- **Automated Analysis**: Parse error to understand failure
- **Reproduction**: Execute command to confirm failure
- **Resolution**: Fix and re-run same command

## Adding Tests to Existing Codebases

When tests do not exist:

1. **Start with critical paths**: What breaks the app?
2. **Add regression tests**: What broke before?
3. **Test at boundaries**: Input validation, API responses
4. **Prioritize determinism**: Avoid flaky tests

## Test Commands by Stack

### Python

```bash
# pytest
pytest -v
pytest tests/ -v --tb=short

# unittest
python -m unittest discover -v
```markdown

### TypeScript/JavaScript

```bash
# Jest
npm test
npx jest --verbose

# Vitest
npm run test
npx vitest run

# Playwright (E2E)
npx playwright test
```markdown

### Go

```bash
go test ./... -v
```markdown

### Rust

```bash
cargo test
```markdown

## The Validation Stack

Combine multiple test types for comprehensive validation:

```markdown
## Validation Commands

1. Lint: `npm run lint`
2. Type Check: `npm run typecheck`
3. Unit Tests: `npm run test:unit`
4. Integration Tests: `npm run test:integration`
5. Build: `npm run build`
6. E2E Tests: `npm run test:e2e`
```markdown

Each layer catches different failure modes.

## Related

- @closed-loop-anatomy.md - The full Request-Validate-Resolve structure
- @validation-commands.md - Patterns for validation commands
- @e2e-test-patterns.md - E2E testing patterns
