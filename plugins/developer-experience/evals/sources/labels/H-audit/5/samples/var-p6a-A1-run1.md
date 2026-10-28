### Assistant final message, turn 1

I read every tooling file in the repo. Four things can go: three are broken or do nothing useful, and one is a wrapper you don't need. I haven't changed anything yet.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. This server can never start.

**2. `[redacted-path]`.** It tells the agent to run `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag, so argparse fails with a usage error (exit 2). Without the flag, `release.py:7` calls `input()`, which an agent can't answer. Its whole purpose is also to skip the confirmation that AGENTS.md says nothing may bypass ("No flags bypass the prompt"). Delete it rather than fix it. Releases are meant to be a human step.

**3. `[redacted-path]` (the `/test` command).** It repeats `make test` and has already drifted from it: it runs `unittest discover -s tests` without `-t .` and without the `cd` to the repo root that `run_tests.sh` does. AGENTS.md already tells the agent to use `make test`, so a second, differing copy only adds upkeep.

**4. `scripts/release.ps1`.** It's a one-line wrapper around `python3 -m bfk.cli release $Version`, and on Windows `python3` often isn't on PATH (`python`/`py` are). Running `python -m bfk.cli release 0.5.0` directly in pwsh does the same thing.

## Keep

- **`scripts/run_tests.sh` and the `Makefile`:** these are the canonical test entry point and are documented in AGENTS.md and README.
- **`make release`:** it's a cheap, documented shortcut, and it keeps the confirmation prompt.
- **`scripts/fmt.sh` and its `PostToolUse` hook:** it checks after every Write or Edit that `bfk/*.py` parses, and it works.
- **`bfk/proc.py`:** it's the shared subprocess helper AGENTS.md requires.

## Docs to update if you drop these

- **AGENTS.md "Tools":** remove the `release.ps1` line. The Windows instruction becomes `python -m bfk.cli release <version>`.
- **`scripts/README.md`:** remove the `release.ps1` line.

This isn't tooling, but `bfk/text.py` (`slugify`) isn't imported anywhere in `bfk`, and it's the only thing the tests cover. You might drop it too, and then the tests should cover `report` instead.

Want me to make these removals and doc edits on a branch?
