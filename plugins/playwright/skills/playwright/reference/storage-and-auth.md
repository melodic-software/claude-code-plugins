# Storage and auth state

Manage cookies, localStorage, sessionStorage, and complete browser state (for auth carry-through across sessions).

## Storage state (the big knob)

Save whole browser state to a file, restore later to skip login:

```bash
# After a successful login:
playwright-cli -s=auth state-save auth.json

# Later, in a fresh session:
playwright-cli -s=auth state-load auth.json
playwright-cli -s=auth open https://app.example.com/dashboard   # already logged in
```

**Never commit state files with real auth tokens.** Add `*.auth-state.json` and `auth.json` to `.gitignore` if used. For this repo's E2E fixtures, prefer test accounts with rotatable tokens.

File format:

```json
{
  "cookies": [{ "name": "session_id", "value": "abc", "domain": "example.com", "path": "/", "httpOnly": true, "secure": true, "sameSite": "Lax" }],
  "origins": [{ "origin": "https://example.com", "localStorage": [{ "name": "theme", "value": "dark" }] }]
}
```

## Cookies

```bash
playwright-cli cookie-list                                    # all
playwright-cli cookie-list --domain=example.com               # filter
playwright-cli cookie-get session_id
playwright-cli cookie-set session_id abc123
playwright-cli cookie-set session_id abc123 --domain=example.com --path=/ --httpOnly --secure --sameSite=Lax
playwright-cli cookie-set remember_me tok --expires=1735689600   # Unix ts
playwright-cli cookie-delete session_id
playwright-cli cookie-clear
```

For multiple cookies at once or complex options, drop into `run-code`:

```bash
playwright-cli run-code "async page => {
  await page.context().addCookies([
    { name: 'session_id', value: 'abc', domain: 'example.com', path: '/', httpOnly: true },
    { name: 'prefs', value: JSON.stringify({ theme: 'dark' }), domain: 'example.com', path: '/' }
  ]);
}"
```

See [running-code.md](running-code.md).

## localStorage

```bash
playwright-cli localstorage-list
playwright-cli localstorage-get token
playwright-cli localstorage-set theme dark
playwright-cli localstorage-set user_settings '{"theme":"dark","lang":"en"}'
playwright-cli localstorage-delete token
playwright-cli localstorage-clear
```

## sessionStorage

Same shape as localStorage:

```bash
playwright-cli sessionstorage-list | get | set | delete | clear
```

## IndexedDB

No first-class CLI commands; use `run-code`:

```bash
playwright-cli run-code "async page => {
  return await page.evaluate(async () => (await indexedDB.databases()));
}"

playwright-cli run-code "async page => {
  await page.evaluate(() => indexedDB.deleteDatabase('myDatabase'));
}"
```

## Auth reuse pattern (the standard flow)

```bash
# Step 1: interactive login, save state
playwright-cli -s=login open https://app.example.com/login --persistent
playwright-cli -s=login snapshot
playwright-cli -s=login fill e1 "user@example.com"
playwright-cli -s=login fill e2 "password123" --submit
playwright-cli -s=login state-save auth.json
playwright-cli -s=login close

# Step 2: subsequent sessions load state and skip login
playwright-cli -s=test state-load auth.json
playwright-cli -s=test open https://app.example.com/dashboard
# ... run tests against authenticated app ...
playwright-cli -s=test close
```

## Security invariants

- Default sessions are in-memory — safer for sensitive operations. Use `--persistent` only when auth carry-through across browser restarts required
- `state-save` files contain raw tokens. Treat as secrets: gitignore, delete after tests, don't share between developers
- Prefer env-var-driven test credentials over hard-coded values in skill examples
