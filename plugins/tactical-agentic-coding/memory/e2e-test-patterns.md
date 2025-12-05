# E2E Test Patterns

End-to-end testing patterns for validating complete user flows.

## Why E2E Tests?

Unit tests validate functions. E2E tests validate **user journeys**.

```text
Unit Test: "Does login() return a token?"
E2E Test: "Can a user navigate to login, enter credentials, and see their dashboard?"
```markdown

## E2E Test Specification Format

From tac-5, the standard E2E test specification:

```markdown
# E2E Test: [Test Name]

## User Story

As a [user type]
I want to [action]
So that [benefit]

## Test Steps

1. Navigate to [URL]
2. Take screenshot of initial state
3. **Verify** [element/condition] is present
4. [Action] - Click/Enter/Select
5. Take screenshot of [state]
6. **Verify** [expected result]
7. [Continue steps...]

## Success Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] [Criterion 3]
```markdown

## Example: Basic Query Test

```markdown
# E2E Test: Basic Query Execution

## User Story

As a user
I want to query data using natural language
So that I can access information without writing SQL

## Test Steps

1. Navigate to http://localhost:5173
2. Take screenshot of initial state
3. **Verify** page title is "Natural Language SQL Interface"
4. **Verify** query input field is present
5. Enter query: "Show me all users"
6. Take screenshot of query input
7. Click Query button
8. **Verify** query results appear within 5 seconds
9. **Verify** SQL translation is displayed
10. Take screenshot of results
11. **Verify** results table contains data rows

## Success Criteria

- [ ] Query input accepts text
- [ ] Query button triggers execution
- [ ] Results display within 5 seconds
- [ ] SQL translation shown
- [ ] Results table has data
```markdown

## Key Patterns

### **Verify** Checkpoints

Mark validation steps with `**Verify**` for clarity:

```markdown
5. **Verify** login button is visible
6. **Verify** error message contains "Invalid credentials"
7. **Verify** user is redirected to /dashboard
```markdown

### Screenshot Capture

Document state at key points:

```markdown
2. Take screenshot of initial state
6. Take screenshot after form submission
10. Take screenshot of success state
```markdown

### Success Criteria Checklist

Explicit pass/fail criteria:

```markdown
## Success Criteria

- [ ] Form validation prevents empty submission
- [ ] Error messages display correctly
- [ ] Success redirects to dashboard
- [ ] User session persists
```markdown

## E2E Test Output Format

Structured JSON for automation:

```json
{
  "test_name": "Basic Query Execution",
  "status": "passed",
  "screenshots": [
    "screenshots/01_initial_state.png",
    "screenshots/02_query_input.png",
    "screenshots/03_results.png"
  ],
  "error": null
}
```text

For failures:

```json
{
  "test_name": "Basic Query Execution",
  "status": "failed",
  "screenshots": [
    "screenshots/01_initial_state.png",
    "screenshots/02_query_input.png"
  ],
  "error": "Step 8 failed: Results did not appear within 5 seconds"
}
```markdown

## E2E Test Organization

Store test specifications in a dedicated location:

```text
.claude/commands/e2e/
  ├── test-basic-query.md
  ├── test-complex-query.md
  ├── test-user-login.md
  └── test-sql-injection.md
```text

Or alongside feature specs:

```text
specs/
  ├── feature-auth.md
  └── e2e/
      └── test-auth-flow.md
```markdown

## Browser Automation Tools

### Playwright (Recommended)

```typescript
// Playwright provides reliable cross-browser testing
import { test, expect } from '@playwright/test';

test('basic query execution', async ({ page }) => {
  await page.goto('http://localhost:5173');
  await expect(page.locator('h1')).toContainText('Natural Language SQL');
  await page.fill('input[name="query"]', 'Show me all users');
  await page.click('button[type="submit"]');
  await expect(page.locator('.results-table')).toBeVisible();
});
```markdown

### Claude Code E2E Pattern

When running E2E tests via Claude Code:

1. Read the test specification file
2. Execute each step using browser tools (if available) or verification commands
3. Capture screenshots at specified points
4. Report structured results

## Security E2E Tests

Test security boundaries:

```markdown
# E2E Test: SQL Injection Protection

## User Story

As a user
I want to be protected from SQL injection attacks
So that my data remains secure

## Test Steps

1. Navigate to application
2. Enter malicious query: "'; DROP TABLE users; --"
3. **Verify** error message appears (not SQL execution)
4. **Verify** database tables remain intact
5. Enter legitimate query: "Show all users"
6. **Verify** query executes normally
```markdown

## Related

- @closed-loop-anatomy.md - The full Request-Validate-Resolve structure
- @test-leverage-point.md - Why tests are the ultimate validation
- @validation-commands.md - Patterns for validation commands
