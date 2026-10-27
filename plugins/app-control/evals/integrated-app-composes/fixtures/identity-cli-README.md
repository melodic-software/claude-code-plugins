# identity driver CLI

`cli/identity <command> [flags]`, one JSON document on stdout under `--json` that names the
environment it ran against, progress on stderr.

| Command | Does |
|---|---|
| `sign-in <account>` | One sign-in attempt for the account, reading its credential from the environment variable `config/defaults.json` names for it; never retries |
| `config` | Prints each setting with its layer; changes nothing |

Flags: `--environment <name>` selects an environment from committed config; `--json`.

Exit codes: 0 signed in; 1 sign-in failed; 2 usage, or an unknown account or environment; 4 refused
by a safety floor (prints the floor, the layer and the value).
