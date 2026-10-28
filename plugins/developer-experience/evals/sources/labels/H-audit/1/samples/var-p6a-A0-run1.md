### Assistant final message, turn 1

I'd drop two things and rewrite one. The core worth keeping is `make test` → `scripts/run_tests.sh`, `AGENTS.md`, and the `bfk` CLI itself.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It launches `tools/ledger_mcp.py`, but there is no `tools/` directory in the repo. It can't start, so it's pure upkeep.

**2. `[redacted-path]` (`/test`).** It repeats the test command with slightly different flags (no `-t .`). `AGENTS.md` already tells the agent to run `make test`, so this is a second copy that can drift from the first.

## Rewrite

**`[redacted-path]` (the release-checker agent).** It runs `python3 -m bfk.cli release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag, so argparse would reject the command and it would never tag anything. Don't add the flag: the confirmation in `bfk/release.py:7` looks intentional (README: "asks before tagging"). Rewrite its step to run `make release VERSION=<version>` so a person still answers the prompt.

## Your call
- **`make release`:** this is also a thin wrapper, but the README documents it and it's harmless. Keep it unless you want the CLI to be the only way in.

## Keep
- `Makefile` `test`, `scripts/run_tests.sh`, `AGENTS.md`: the one documented way to build and test, which both people and the agent use.
- `scripts/fmt.sh` and its `PostToolUse` hook in `.claude/settings.json`: leave as is. It checks after every Write or Edit that `bfk/*.py` still parses, and it works.
- `scripts/release.ps1`: leave as is. It's the Windows entry point for `bfk release`, where `make` usually isn't available.
- `bfk` CLI (`bfk/cli.py`): still needed, it's the product itself.

I worked only from reading the files and didn't run anything, because shell access was denied in this session. I also haven't changed anything. I can make these removals on a branch if you'd like.
