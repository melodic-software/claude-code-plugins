### Assistant final message, turn 1

Four of the repo's ten dev-tooling pieces can go. Two are broken now, and one copies a command that already exists. I couldn't run anything (shell access was denied in this session), so everything below comes from reading the files.

## Drop

1. **`.mcp.json` (the `ledger` MCP server).** It launches `tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. Every session tries to start it and fails. Delete the file, or restore the script if someone still needs it.

2. **`[redacted-path]`.** It's broken and unsafe:
   - It runs `bfk.cli release --yes <version>`, but `cli.py` has no `--yes` flag. Argparse will exit with an error, so the agent can't do its job.
   - Its stated purpose is to skip the "Tag release?" confirmation in `bfk/release.py:7`. That prompt is the only safeguard on tagging, and the README says "asks before tagging." An agent that tags with no human check is the kind of automation you'd want gone anyway.

   Releases are rare and already have one documented path (`make release VERSION=…`), so drop the agent instead of fixing it.

3. **The `PostToolUse` hook in `.claude/settings.json` plus `scripts/fmt.sh`.** It runs after every Write or Edit. Despite the name, `fmt.sh` doesn't format anything: it only checks that `bfk/*.py` parses. The test run catches that anyway, since importing a module that doesn't parse fails. You'd be paying for a script run on every edit for almost no benefit, and the misleading name will confuse people. It's also missing from `scripts/README.md`. With the hook gone, `settings.json` is empty and can be deleted.

4. **`scripts/release.ps1`.** It's a five-line wrapper around `python3 -m bfk.cli release $Version`, which is the same thing the `make release` target does, so it's a third way to cut a release. On Windows, `python3` often isn't on PATH either, so it may not work there. Windows users can run the Python command directly. Once it's gone, `scripts/README.md` would only describe `run_tests.sh`, so fold that one line into the main README and delete it too.

## Keep

- **`Makefile` (`test`, `release`).** This is the documented entry point in both README and AGENTS.md, and it's tiny.
- **`/test` command.** A short in-session shortcut for running the tests. It's cheap, so keep it.
- **`scripts/run_tests.sh`.** It's the single source of the test command. If you want one fewer file, you could inline its one line into the Makefile and update AGENTS.md and the README. That's optional and a small gain.

## End state

You'd be left with a Makefile, one test script, the `/test` command, and no `.mcp.json` config. That's two ways to run the tests and one way to release, and the release still asks before tagging.

Want me to make these deletions and update the README and AGENTS.md on a branch?
