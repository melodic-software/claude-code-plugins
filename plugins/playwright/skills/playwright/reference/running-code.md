# Running custom Playwright code (`run-code`)

Use `run-code` for advanced scenarios not covered by CLI commands. Argument is an `async page => { ... }` function body.

## Contents

- [Syntax](#syntax)
- [Common recipes](#common-recipes)
- [When to reach for `run-code`](#when-to-reach-for-run-code)
- [File input (`--filename`)](#file-input---filename)

## Syntax

```bash
playwright-cli run-code "async page => {
  // Playwright code. 'page' is the Playwright Page object.
  // 'page.context()' is the BrowserContext.
}"

# From a file (avoids quoting hell)
playwright-cli run-code --filename=script.js
```

Return values from the function are printed as command result.

Treat the `run-code` body as a sandbox, not full Node.js: pass values such as secrets in from the shell as JSON-encoded literals (see the login example below), never through `process.env` or a Node module inside the body.

- **Pointer**: when you need to know which globals the `run-code` sandbox provides, fetch the [v0.1.22 release notes](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.22) live. **As of**: 2026-10-04. **Recheck trigger**: the frontmatter `upstream-version` moves.

## Common recipes

### Geolocation

```bash
playwright-cli run-code "async page => {
  await page.context().grantPermissions(['geolocation']);
  await page.context().setGeolocation({ latitude: 37.7749, longitude: -122.4194 });
}"
```

Clear: `await page.context().clearPermissions();`

### Permissions

```bash
playwright-cli run-code "async page => {
  await page.context().grantPermissions([
    'geolocation', 'notifications', 'camera', 'microphone', 'clipboard-read', 'clipboard-write'
  ]);
}"
# Origin-scoped:
playwright-cli run-code "async page => {
  await page.context().grantPermissions(['clipboard-read'], { origin: 'https://example.com' });
}"
```

### Media emulation

```bash
playwright-cli run-code "async page => { await page.emulateMedia({ colorScheme: 'dark' }); }"
playwright-cli run-code "async page => { await page.emulateMedia({ reducedMotion: 'reduce' }); }"
playwright-cli run-code "async page => { await page.emulateMedia({ media: 'print' }); }"
```

### Wait strategies

```bash
# Wait for network idle
playwright-cli run-code "async page => { await page.waitForLoadState('networkidle'); }"

# Wait for element hidden
playwright-cli run-code "async page => {
  await page.locator('.loading').waitFor({ state: 'hidden' });
}"

# Wait for predicate
playwright-cli run-code "async page => {
  await page.waitForFunction(() => window.appReady === true);
}"

# Wait for URL
playwright-cli run-code "async page => { await page.waitForURL('**/dashboard'); }"
```

### Frames and iframes

```bash
playwright-cli run-code "async page => {
  const frame = page.locator('iframe#my-iframe').contentFrame();
  await frame.locator('button').click();
}"

playwright-cli run-code "async page => {
  return page.frames().map(f => f.url());
}"
```

### File downloads

```bash
playwright-cli run-code "async page => {
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Download' }).click();
  const download = await downloadPromise;
  await download.saveAs('./downloaded-file.pdf');
  return download.suggestedFilename();
}"
```

### Clipboard

```bash
# Read (requires permission)
playwright-cli run-code "async page => {
  await page.context().grantPermissions(['clipboard-read']);
  return await page.evaluate(() => navigator.clipboard.readText());
}"

# Write
playwright-cli run-code "async page => {
  await page.evaluate(text => navigator.clipboard.writeText(text), 'Hello clipboard!');
}"
```

### Page info

```bash
playwright-cli run-code "async page => ({
  title: await page.title(),
  url: page.url(),
  viewport: page.viewportSize(),
})"
```

### JavaScript execution with args

```bash
playwright-cli run-code "async page => {
  const multiplier = 5;
  return await page.evaluate(m => document.querySelectorAll('li').length * m, multiplier);
}"
```

### Error handling

```bash
playwright-cli run-code "async page => {
  try {
    await page.getByRole('button', { name: 'Submit' }).click({ timeout: 1000 });
    return 'clicked';
  } catch (e) {
    return 'element not found';
  }
}"
```

### Complex workflows (login + save state)

```bash
playwright-cli run-code "async page => {
  await page.goto('https://example.com/login');
  await page.getByRole('textbox', { name: 'Email' }).fill('user@example.com');
  await page.getByRole('textbox', { name: 'Password' }).fill($(node -p 'JSON.stringify(process.env.E2E_TEST_PASSWORD ?? "")'));
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('**/dashboard');
  await page.context().storageState({ path: 'auth.json' });
  return 'Login successful';
}"
```

The shell runs the `node -p` substitution before `run-code` sees the code, and `JSON.stringify` turns the value into one quoted JavaScript string, so no character in it can end the string and run as code. Never splice a raw `$VAR` between quotes in a `run-code` body. Set `E2E_TEST_PASSWORD` in your own environment first.

## When to reach for `run-code`

| Need | Tool |
|---|---|
| Basic interaction (click, fill, navigate) | CLI commands |
| Storage state save/restore | `state-save`/`state-load` |
| Static response mock | `route` CLI |
| Geolocation, permissions, media emulation | `run-code` |
| Conditional mocking, response modification | `run-code` (see [network-mocking.md](network-mocking.md)) |
| Multi-step deterministic flow in one call | `run-code` with `--filename` |

## File input (`--filename`)

For larger scripts, keep in `.js` files and invoke:

```bash
playwright-cli run-code --filename=tests/e2e/checkout-flow.js
```

File exports the same `async page => { ... }` shape, just unquoted. Lets you use proper editors, syntax highlighting, and lint.
