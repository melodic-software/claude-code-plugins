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

## Spec-driven workflow (plan → generate → heal)

For a whole feature rather than one ad-hoc session, drive test authoring from a written spec instead of an ungoverned exploration session. All three stages debug against a **seed test** — a minimal test that lands the page in the state every scenario starts from (navigation, login, feature flags) — via `npx playwright test <seed> --debug=cli` (background) + `playwright-cli attach tw-XXXX`, never by opening the app URL directly (that skips custom setup the seed performs).

1. **Plan** — explore the app through the attached seed session (`snapshot`, `click`, `eval`), mapping interactive surfaces, journeys, edge cases, and persistence. Write findings to `specs/<feature>.plan.md`: one `## Test Scenarios` group per seed, each scenario a `<kebab-case-name>` with numbered `Steps:` and `- expect:` bullets for observable outcomes. Scenarios never chain — each starts fresh from the seed.
2. **Generate** — for each targeted scenario, re-attach to the seed and walk its `Steps:` one at a time with `playwright-cli`, treating the spec as the plan and the live app as ground truth (a vague or stale step gets corrected in the spec, then generation continues). Collect the emitted Playwright TypeScript per action, add an assertion for each `- expect:` bullet, and write one test file per scenario at the spec's given path. Never run scenarios in parallel — they share the seed session.
3. **Heal** — run the suite, take failures one at a time: attach to the failing test in `--debug=cli`, step to just before the failure, and diagnose with `snapshot`/`console`/`network` (selector drift, timing, stale assertion text are the usual causes). Fix the test, confirm green, then reconcile the spec: a purely technical fix (locator drift) leaves the spec alone; a fix that changes user-visible behavior updates the spec; anything ambiguous (app regression vs. intentional change) stops and asks the user rather than guessing.

## Running generated tests

See upstream `../vendor/references/playwright-tests.md` for `npx playwright test --debug=cli` debugging flow — attach `playwright-cli` to a paused test and step through interactively.

Short version:

```bash
PLAYWRIGHT_HTML_OPEN=never npx playwright test
PLAYWRIGHT_HTML_OPEN=never npx playwright test --debug=cli
# ... prints "Debugging instructions for 'tw-abcdef' session" ...
playwright-cli attach tw-abcdef     # inspect the paused test
```
