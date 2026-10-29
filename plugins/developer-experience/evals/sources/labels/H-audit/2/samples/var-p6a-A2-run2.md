### Assistant final message, turn 1

I audited every dev tool and automation in the repo and didn't change anything. Two things are worth dropping, and both are broken. Everything else is in use.

## Drop these

**1. The `ledger` server in `.mcp.json`: it's broken.**
`.mcp.json:7` starts `tools/ledger_mcp.py`, but there's no `tools/` folder in the repo, so this server can't start. Nothing else mentions it.
Basis: verified (the file list has no `tools/`, and a search found no other mention of `ledger`).

**2. The `release-checker` agent in `[redacted-path]`: it's broken, and it tries to skip a safety prompt.**
Step 2 (`release-checker.md:9`) runs `bfk release --yes`, but `bfk release` has no `--yes` option (`bfk/cli.py:13-14`), so that step always fails. Your conventions also say no option may skip the release confirmation (`docs/conventions[redacted].md:8`). So beyond being broken, the agent's instructions ask it to get around a rule you set on purpose. People release with `make release` (`README.md:8`) and `scripts/release.ps1`.
Basis: verified (the code lines above).

## Keep these

| Item | Why | Basis |
|---|---|---|
| `make test` → `scripts/run_tests.sh` | `AGENTS.md`, `README.md:6` and the conventions file (line 10) all point to it | verified |
| `make release` | `README.md:8` | verified |
| the `/test` command | A short in-session shortcut for running the tests; nothing needs to change | judgment |
| `scripts/release.ps1` | The Windows version of `make release`. Windows is a supported platform (`[redacted].md:27`) | verified |
| `bfk` command (`report`, `release`), registered in `pyproject.toml:9` | It's the team's main tool and is documented in the conventions file (lines 8–9) | verified |
| `scripts/fmt.sh` and the edit hook in `.claude/settings.json:5-9` | The hook is its only user. Despite the "fmt" name, it doesn't format anything: it only checks that each `bfk/*.py` file parses, after every edit. It works and costs little, but it isn't documented anywhere. If you want to cut further, this is the next candidate. | judgment |

There are no git hooks (only git's default `.sample` files, and no custom hooks folder in `.git/config`) and no CI setup. For each item, I checked the Makefile, the scripts, `.claude/` settings, agents and commands, `.mcp.json`, `README.md`, `scripts/README.md`, `AGENTS.md` and the conventions file.

## Other findings

- **The conventions file is out of date.** `docs/conventions[redacted].md` doesn't mention `fmt.sh`, the edit hook, the Makefile, the `/test` command, the agent, or the MCP server. Run `[redacted]` to refresh it once you've decided what to drop.
- Before deleting anything, you can get a second opinion from `/overengineering:justify`. That plugin isn't installed: `claude plugin install overengineering@<marketplace>`.

## Your call

Each of these needs a separate yes from you:
1. Delete the `ledger` entry from `.mcp.json`.
2. Delete `[redacted-path]`.
3. Optionally, delete `scripts/fmt.sh` and its hook in `.claude/settings.json`.
