# control-claude-code commands

Read-only commands drive runs from this control skill. Every other driving command is
`driver/driver.mjs`.

| Command | Flags | Prints | Exit codes |
|---|---|---|---|
| `cli/account.mjs` | none | The signed-in email and organization name from `claude auth status --json`, one per line, for the `## Mask` `values:` line. It never writes them to a file. Under API-key auth that names neither, it prints `none: API-key auth has no signed-in account` instead, and with no login at all (`loggedIn` false, `authMethod` `none`, as an `--unattended` capture sees it) `none: no account is signed in` | 0 printed; 1 `claude auth status` failed, or named neither under any other auth; 2 an argument was given |
