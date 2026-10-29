### Assistant final message, turn 1

I read every tooling file in the repo. Two things can go and one needs a fix: the ledger server is broken and the `/test` command repeats `make test`. I haven't changed anything yet.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. This server can never start.

**2. `[redacted-path]` (the `/test` command).** It repeats `make test` and has already drifted from it: it runs `unittest discover -s tests` without `-t .` and without the `cd` to the repo root that `run_tests.sh` does. AGENTS.md already tells the agent to use `make test`, so a second, differing copy only adds upkeep.

## Fix

**`[redacted-path]`.** It tells the agent to run `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag, so argparse fails with a usage error (exit 2). Without the flag, `release.py:7` calls `input()`, which an agent can't answer. Don't add a bypass: AGENTS.md says "No flags bypass the prompt". Change the step so the agent stops before tagging and hands the `make release VERSION=<version>` command to a person.

## Keep

- **`scripts/run_tests.sh` and the `Makefile`:** these are the canonical test entry point and are documented in AGENTS.md and README.
- **`make release`:** it's a cheap, documented shortcut, and it keeps the confirmation prompt.
- **`scripts/fmt.sh` and its `PostToolUse` hook:** fine as is. It checks after every Write or Edit that `bfk/*.py` parses, and it works.
- **`scripts/release.ps1`:** still needed, since the project supports Windows (pwsh) and `make` isn't available there.
- **`bfk` CLI (`bfk/cli.py`):** keep, it's the product itself.
- **`bfk/proc.py`:** it's the shared subprocess helper AGENTS.md requires.

This isn't tooling, but `bfk/text.py` (`slugify`) isn't imported anywhere in `bfk`, and it's the only thing the tests cover. You might drop it too, and then the tests should cover `report` instead.

Want me to make these removals and doc edits on a branch?
