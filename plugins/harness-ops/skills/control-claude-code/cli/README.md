# control-claude-code commands

Read-only commands drive runs from this control skill. Every other driving command is
`driver/driver.mjs`. Each command answers `--help`. `node driver/driver.mjs --help` lists the
driver's verbs, and `node driver/driver.mjs <verb> --help` prints one verb's flags. A driver verb
that writes or sends (`launch`, `type`, `screenshot`, `record`, `stop`, `ready`, `log`) takes
`--dry-run`: it checks its arguments, prints what it would do and does nothing.

Each dry run's trust mark, per the app-control contract's "Writing the driver CLI":

- `launch`: trusted. `driver/driver.test.mjs` "launch --dry-run prints the claude command line and
  reserves no session" sees no session lock file written.
- `log`: trusted. `driver/driver.test.mjs` "log --dry-run prints the print-mode command line and
  writes no --out file" sees no `--out` file written.
- `type`, `record stop` and `stop`: trusted. `driver/driver.test.mjs` "--dry-run on a session verb
  prints the request and sends nothing" runs each with no session running and sees it print the
  request: a request to that session would have thrown, so no session received one.
- `screenshot`: untrusted. That test sees no request sent, but not that no capture file was written.
- `record start` and `ready`: untrusted. No run has watched their dry run.

| Command | Flags | Prints | Exit codes |
|---|---|---|---|
| `cli/account.mjs` | `--session <name>`, else the one session running; `--help` | The driven session's email and organization name, one per line, for the `## Mask` `values:` line: its session holder runs `claude auth status --json` in that session's own launch environment, never the caller's. It never writes them to a file. When the session runs on the `ANTHROPIC_API_KEY` its launch kept and the status names neither, it prints `none: API-key auth has no signed-in account` instead | 0 printed; 1 no session or several running, the holder's `claude auth status` failed, it named neither outside that key auth, or the holder sent anything else; 2 a bad argument or session name |
