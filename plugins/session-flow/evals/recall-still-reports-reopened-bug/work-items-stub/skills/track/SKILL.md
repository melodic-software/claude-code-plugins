---
description: "Backlog reads through the bound tracker: search open and closed items, view one item with its comments and state history. Use when another skill searches or reads tracker items."
argument-hint: "[search|view] [args]"
user-invocable: true
disable-model-invocation: false
---

# Track (eval stand-in)

This tracker holds exactly the items below. Answer from them; read nothing else.

| Id | Title | State | Type | Labels |
|----|-------|-------|------|--------|
| `github:acme/web#57` | Login redirect loop after SSO sign-in | open | Bug | `area: auth` |
| `github:acme/web#12` | Document the SSO login flow | closed (2026-07-30) | Task | `docs` |

## `search <query>`

Match the query against each title, ignoring case, word by word: an item matches when its title
holds any word of the query. Print the matches grouped as:

```markdown
### Open Items (N matches)

| # | Item | Type | Labels | Assignee |
|---|------|------|--------|----------|

### Closed Items (N matches)

| # | Item | Closed |
|---|------|--------|
```

## `view <id> [--comments] [--history]`

Print one fenced JSON block for the item: `{"id", "title", "state", "url", "labels", "body"}`,
`url` `https://github.com/acme/web/issues/<number>`. With `--comments` add `"comments"`; with
`--history` add `"state_history"`.

- `github:acme/web#57`: body `After signing in with SSO the browser bounces between /login and
  /callback until it gives up.`, comments `[]`, state history:

  ```json
  {"available": true, "events": [
    {"state": "closed", "at": "2026-09-02T14:10:00Z", "actor": "dev-a"},
    {"state": "reopened", "at": "2026-09-10T08:45:00Z", "actor": "reporter-b"}
  ], "reopen_count": 1, "reason": null}
  ```

- `github:acme/web#12`: body `Write up how SSO sign-in works.`, comments `[]`, state history:

  ```json
  {"available": true, "events": [
    {"state": "closed", "at": "2026-07-30T09:00:00Z", "actor": "dev-a"}
  ], "reopen_count": 0, "reason": null}
  ```

Any other id: print `not found` and stop.
