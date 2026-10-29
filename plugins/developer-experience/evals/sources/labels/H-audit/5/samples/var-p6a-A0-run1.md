### Assistant final message, turn 1

I'd drop four things. The core worth keeping is `make test` → `scripts/run_tests.sh`, `AGENTS.md`, and the `bfk` CLI itself.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It launches `tools/ledger_mcp.py`, but there is no `tools/` directory in the repo. It can't start, so it's pure upkeep.

**2. `[redacted-path]`.** It's broken, and it works against a safety step you built on purpose.
- It runs `python3 -m bfk.cli release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse would reject the command and it would never tag anything.
- The `--yes` was meant to skip the confirmation in `bfk/release.py:7`. That confirmation looks intentional (README: "asks before tagging"). A release tag gets pushed and published, so it should stay a human step rather than something the agent does on its own.
- Releasing is already just `make release VERSION=x`, so the agent saves nothing.

**3. `[redacted-path]` (`/test`).** It repeats the test command with slightly different flags (no `-t .`). `AGENTS.md` already tells the agent to run `make test`, so this is a second copy that can drift from the first.

**4. `scripts/release.ps1`.** It's a one-line wrapper around `python3 -m bfk.cli release $Version`, which Windows users can run directly. It also assumes a `python3` command exists, which on Windows it often doesn't (`py` or `python` is more common). After removing it, cut its line from `scripts/README.md`.

## Your call
- **`make release`:** this is also a thin wrapper, but the README documents it and it's harmless. Keep it unless you want the CLI to be the only way in.

## Keep
- `Makefile` `test`, `scripts/run_tests.sh`, `AGENTS.md`: the one documented way to build and test, which both people and the agent use.
- `scripts/fmt.sh` and its `PostToolUse` hook in `.claude/settings.json`: it checks after every Write or Edit that `bfk/*.py` still parses, and it works.

I worked only from reading the files and didn't run anything, because shell access was denied in this session. I also haven't changed anything. I can make these removals on a branch if you'd like.
