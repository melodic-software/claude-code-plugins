# control-claude-code commands

Read-only commands drive runs from this control skill. Every other driving command is
`driver/driver.mjs`.

| Command | Flags | Prints | Exit codes |
|---|---|---|---|
| `cli/account.mjs` | `--session <name>`, else the one session running | The driven session's email and organization name, one per line, for the `## Mask` `values:` line: its session holder runs `claude auth status --json` in that session's own launch environment, never the caller's. It never writes them to a file. When the session runs on the `ANTHROPIC_API_KEY` its launch kept and the status names neither, it prints `none: API-key auth has no signed-in account` instead | 0 printed; 1 no session or several running, the holder's `claude auth status` failed, it named neither outside that key auth, or the holder sent anything else; 2 a bad argument or session name |
