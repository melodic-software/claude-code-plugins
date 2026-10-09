# Generating Playwright tests from CLI sessions

Every CLI command prints the equivalent Playwright TypeScript code. Copy-paste into a `.spec.ts` file to turn exploration into a regression test.

## Contents

- [How it works](#how-it-works)
- [Turning a session into a test](#turning-a-session-into-a-test)
- [Workflow](#workflow)
- [Best practices](#best-practices)
- [Spec-driven workflow (plan → generate → heal)](#spec-driven-workflow-plan--generate--heal)
- [Running generated tests](#running-generated-tests)

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
  await page.getByRole('textbox', { name: 'Password' }).fill(process.env.E2E_TEST_PASSWORD!);
  await page.getByRole('button', { name: 'Sign In' }).click();

  // Add assertions manually — the CLI captures actions, not expectations:
  await expect(page).toHaveURL(/.*dashboard/);
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
});
```

## Workflow

1. **Open and explore**: `playwright-cli open <url>` + `snapshot` to see the page
2. **Perform the flow**: each click/fill/press emits code into stdout
3. **Collect the emitted code**: copy the `### Ran Playwright code` blocks from the output (do NOT use `--raw`, which strips them)
4. **Wrap in a test**: add `test(...)` + `import` + assertions
5. **Run to verify**: `PLAYWRIGHT_HTML_OPEN=never npx playwright test tests/e2e/login.spec.ts`

## Best practices

### Prefer role-based locators

CLI emits role-based locators by default (`getByRole('button', { name: 'Submit' })`). These survive CSS changes. Avoid converting to CSS selectors. For an element you did not act on, ask the CLI for its locator rather than writing one by hand:

```bash
playwright-cli generate-locator e5 --raw   # prints the Playwright locator for ref e5
```

### Add assertions manually

CLI captures what you DID, not what you EXPECTED. The expected value comes from the requirement or acceptance criterion the test checks, not from what the page shows today: an expectation copied from the running app records its actual behavior, bugs included (see [Where expectations come from](#where-expectations-come-from)). After pasting generated code into a test, add:

```typescript
await expect(page).toHaveURL(/.*dashboard/);
await expect(page.getByText('Success')).toBeVisible();
await expect(page.getByRole('alert')).toContainText('Saved');
```

### Snapshot before recording

Taking `playwright-cli snapshot` before interacting documents page structure the test expects. If page changes later, snapshot diff tells you what drifted.

### Capture emitted code into a file

For mechanical capture into a file, redirect the normal output. `--raw` is the wrong mode here (it strips page status, generated code, and snapshots, returning only the result value):

```bash
playwright-cli open https://example.com | tee -a capture.log
playwright-cli click e3 | tee -a capture.log
# ... then pull the code lines out of the "### Ran Playwright code" blocks
```

Not as clean as hand-curating, but useful for rapid iteration.

## Spec-driven workflow (plan → generate → heal)

For a whole feature rather than one ad-hoc session, drive test authoring from a written spec instead of an ungoverned exploration session. A **seed test** is a minimal test that lands the page in the state every scenario starts from (navigation, login, feature flags). All three stages debug against it via `npx playwright test <seed> --debug=cli` (background) + `playwright-cli attach tw-XXXX`, never by opening the app URL directly (that skips custom setup the seed performs).

1. **Plan**: explore the app through the attached seed session (`snapshot`, `click`, `eval`), mapping interactive surfaces, journeys, edge cases, and persistence. Write findings to `specs/<feature>.plan.md`: one `## Test Scenarios` group per seed, each scenario a `<kebab-case-name>` with numbered `Steps:` and `- expect:` bullets for observable outcomes. Exploration supplies the steps; each `- expect:` bullet names the requirement or acceptance criterion it comes from. An outcome you only observed, with no requirement behind it, is marked unconfirmed and goes to the user, not into the suite as fact. Scenarios never chain. Each starts fresh from the seed.
2. **Generate**: for each targeted scenario, re-attach to the seed and walk its `Steps:` one at a time with `playwright-cli`. The spec is the oracle and the live app is the subject under test: the app tells you how to reach a state (locators, waits, navigation), never what the outcome should be. A vague or stale step gets corrected in the spec, then generation continues; an outcome the app contradicts is a finding to report, not a spec edit. Collect the emitted Playwright TypeScript per action, add an assertion for each `- expect:` bullet so every `expect` traces to a requirement, and write one test file per scenario at the spec's given path. Never run scenarios in parallel. They share the seed session.
3. **Heal**: run the suite, take failures one at a time. Diagnose from the evidence the run left before re-running anything: the retained trace through the terminal trace loop and the failure's error context ([tracing-and-video.md](tracing-and-video.md#reading-a-failed-playwrighttest-run)). When that does not settle it, attach to the failing test in `--debug=cli`, step to just before the failure, and inspect with `snapshot`/`console`/`network`. Then classify:
   - **Test defect** (selector drift, timing, assertion text the spec does not fix): fix the test and confirm green. A purely technical fix leaves the spec alone.
   - **App defect** (the app contradicts a `- expect:` bullet's requirement): never patch the expectation to match the app. Mark the test failing or skipped with the reason and the requirement it breaks (`test.fail()` or `test.fixme()`), and report it to the user.
   - **Ambiguous** (regression or intentional change, or a spec you suspect is stale): stop and ask the user. The spec changes only on their word.

### Where expectations come from

Basis for the Plan and Generate rules above: three independent research groups found that LLM test generators, run against buggy code on benchmark repositories, mostly write oracles that assert what the code does rather than what it should do, so the tests pass over bugs and can validate them ([arXiv 2410.21136](https://arxiv.org/abs/2410.21136), [2412.14137](https://arxiv.org/abs/2412.14137), [2607.22883](https://arxiv.org/abs/2607.22883)). They measured test generation, not an interactive agent driving a browser; applying it to expectations read off a live app is an inference. For the general rule on where an expected value may come from, see `/testing:test-value`.

Upstream's healer agent carries the same guardrail: when it believes the functionality is broken it skips the test rather than patching it green. Playwright's Test Agents (`npx playwright init-agents --loop=claude`) are the upstream alternative to this hand-driven loop, generating planner, generator and healer definitions into the project.

- **Pointer**: [Playwright Test Agents](https://playwright.dev/docs/test-agents) for the setup command, the agents' outputs and the healer's behavior. **As of**: 2026-10-06, Playwright 1.63. **Recheck trigger**: a Playwright release whose notes touch Test Agents or `init-agents`, or this loop and the healer disagreeing on what to do with a broken feature.

## Running generated tests

For the `npx playwright test --debug=cli` debugging flow, see upstream `../vendor/references/playwright-tests.md`. Attach `playwright-cli` to a paused test and step through interactively.

Short version:

```bash
PLAYWRIGHT_HTML_OPEN=never npx playwright test
PLAYWRIGHT_HTML_OPEN=never npx playwright test --debug=cli
# ... prints "Debugging instructions for 'tw-abcdef' session" ...
playwright-cli attach tw-abcdef     # inspect the paused test
```
