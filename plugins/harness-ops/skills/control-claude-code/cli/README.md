# control-claude-code commands

Read-only commands drive runs from this control skill. Every other driving command is
`driver/driver.mjs`.

| Command | Flags | Prints | Exit codes |
|---|---|---|---|
| `cli/account.mjs` | none | The signed-in email and organization name from `claude auth status --json`, one per line, for the `## Mask` `values:` line. It never writes them to a file. Under API-key auth (`authMethod` `api_key`) with neither, it prints the one line `none: API-key auth has no signed-in account` | 0 printed; 1 `claude auth status` failed, or named neither under any other auth method; 2 an argument was given |
