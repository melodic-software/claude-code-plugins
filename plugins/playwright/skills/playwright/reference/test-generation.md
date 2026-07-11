# Generating Playwright tests from CLI sessions

Every CLI command prints the equivalent Playwright TypeScript code. Copy-paste into a `.spec.ts` file to turn exploration into a regression test.

## How it works

```text
$ playwright-cli open https://example.com/login
### Ran Playwright code
    await page.goto('https://example.com/login');

$ playwright-cli fill e1 "user@example.com"
### Ran Playwright code
    await page.getByRole('textbox', { name: 'Email' }).fill('user@example.com');
```

Each command contributes one or more Playwright API calls using **role-based locators** where possible.

## Turning a session into a test

```typescript
// tests/e2e/login.spec.ts
import { test, expect } from '@playwright/test';

test('login flow', async ({ page }) => {
  // Generated from a playwright-cli session:
  await page.goto('https://example.com/login');
  await page.getByRole('textbox', { name: 'Email' }).fill('user@example.com');
  await page.getByRole('textbox', { name: 'Password' }).fill('password123');
  await page.getByRole('button', { name: 'Sign In' }).click();

  // Add assertions manually — the CLI captures actions, not expectations:
  await expect(page).toHaveURL(/.*dashboard/);
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
});
```

## Workflow

1. **Open and explore** — `playwright-cli open <url>` + `snapshot` to see the page
2. **Perform the flow** — each click/fill/press emits code into stdout
3. **Collect the emitted code** — copy the `### Ran Playwright code` blocks from the output (do NOT use `--raw`, which strips them)
4. **Wrap in a test** — add `test(...)` + `import` + assertions
5. **Run to verify** — `PLAYWRIGHT_HTML_OPEN=never npx playwright test tests/e2e/login.spec.ts`

## Best practices

### Prefer role-based locators

CLI emits role-based locators by default (`getByRole('button', { name: 'Submit' })`). These survive CSS changes. Avoid converting to CSS selectors.

### Add assertions manually

CLI captures what you DID, not what you EXPECTED. After pasting generated code into a test, add:

```typescript
await expect(page).toHaveURL(/.*dashboard/);
await expect(page.getByText('Success')).toBeVisible();
await expect(page.getByRole('alert')).toContainText('Saved');
```

### Snapshot before recording

Taking `playwright-cli snapshot` before interacting documents page structure the test expects. If page changes later, snapshot diff tells you what drifted.

### Capture emitted code into a file

For mechanical capture into a file, redirect the normal output — `--raw` is the wrong mode here (it strips page status, generated code, and snapshots, returning only the result value):

```bash
playwright-cli open https://example.com | tee -a capture.log
playwright-cli click e3 | tee -a capture.log
# ... then pull the code lines out of the "### Ran Playwright code" blocks
```

Not as clean as hand-curating, but useful for rapid iteration.

## Running generated tests

See upstream `../vendor/references/playwright-tests.md` for `npx playwright test --debug=cli` debugging flow — attach `playwright-cli` to a paused test and step through interactively.

Short version:

```bash
PLAYWRIGHT_HTML_OPEN=never npx playwright test
PLAYWRIGHT_HTML_OPEN=never npx playwright test --debug=cli
# ... prints "Debugging instructions for 'tw-abcdef' session" ...
playwright-cli attach tw-abcdef     # inspect the paused test
```
