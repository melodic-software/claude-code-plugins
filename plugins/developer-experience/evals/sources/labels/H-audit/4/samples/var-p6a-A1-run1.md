### Assistant final message, turn 1

I read every tooling file in the repo. Four things can go and one needs a fix: three of the four are broken or do nothing useful, and one is a wrapper you don't need. I haven't changed anything yet.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. This server can never start.

**2. The `PostToolUse` hook in `.claude/settings.json` and `scripts/fmt.sh`.** The name suggests a formatter, but the script only checks that `bfk/*.py` parses. It runs after every Write/Edit, whatever file was touched. When the check fails it exits 1, which Claude Code treats as a non-blocking error, so the agent normally never sees it. The next `make test` import would catch a syntax error anyway. It also depends on `bash`, which breaks the Windows/pwsh platform you support. Neither the hook nor the script is in `scripts/README.md` or AGENTS.md.

**3. `[redacted-path]` (the `/test` command).** It repeats `make test` and has already drifted from it: it runs `unittest discover -s tests` without `-t .` and without the `cd` to the repo root that `run_tests.sh` does. AGENTS.md already tells the agent to use `make test`, so a second, differing copy only adds upkeep.

**4. `scripts/release.ps1`.** It's a one-line wrapper around `python3 -m bfk.cli release $Version`, and on Windows `python3` often isn't on PATH (`python`/`py` are). Running `python -m bfk.cli release 0.5.0` directly in pwsh does the same thing.

## Fix

**`[redacted-path]`.** It tells the agent to run `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag, so argparse fails with a usage error (exit 2). Without the flag, `release.py:7` calls `input()`, which an agent can't answer. Don't add a bypass: AGENTS.md says "No flags bypass the prompt". Change the step so the agent stops before tagging and hands the `make release VERSION=<version>` command to a person.

## Keep

- **`scripts/run_tests.sh` and the `Makefile`:** these are the canonical test entry point and are documented in AGENTS.md and README.
- **`make release`:** it's a cheap, documented shortcut, and it keeps the confirmation prompt.
- **`bfk/proc.py`:** it's the shared subprocess helper AGENTS.md requires.

## Docs to update if you drop these

- **AGENTS.md "Tools":** remove the `release.ps1` line. The Windows instruction becomes `python -m bfk.cli release <version>`.
- **`scripts/README.md`:** remove the `release.ps1` line.

This isn't tooling, but `bfk/text.py` (`slugify`) isn't imported anywhere in `bfk`, and it's the only thing the tests cover. You might drop it too, and then the tests should cover `report` instead.

Want me to make these removals and doc edits on a branch?
