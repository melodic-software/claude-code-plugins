### Assistant final message, turn 1

Four of the repo's ten dev-tooling pieces can go. Two are broken now, and two copy commands that already exist. I couldn't run anything (shell access was denied in this session), so everything below comes from reading the files.

## Drop

1. **`.mcp.json` (the `ledger` MCP server).** It launches `tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. Every session tries to start it and fails. Delete the file, or restore the script if someone still needs it.

2. **`[redacted-path]`.** It's broken and unsafe:
   - It runs `bfk.cli release --yes <version>`, but `cli.py` has no `--yes` flag. Argparse will exit with an error, so the agent can't do its job.
   - Its stated purpose is to skip the "Tag release?" confirmation in `bfk/release.py:7`. That prompt is the only safeguard on tagging, and the README says "asks before tagging." An agent that tags with no human check is the kind of automation you'd want gone anyway.

   Releases are rare and already have one documented path (`make release VERSION=…`), so drop the agent instead of fixing it.

3. **`[redacted-path]`.** This copies the test command and has already drifted from it: it runs `unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh` uses. `AGENTS.md` already tells the agent to use `make test`, so this is a second copy to keep in sync. If you want to keep the `/test` shortcut, cut it down to "Run `make test` and report the result."

4. **`scripts/release.ps1`.** It's a five-line wrapper around `python3 -m bfk.cli release $Version`, which is the same thing the `make release` target does, so it's a third way to cut a release. On Windows, `python3` often isn't on PATH either, so it may not work there. Windows users can run the Python command directly. Once it's gone, `scripts/README.md` would only describe `run_tests.sh`, so fold that one line into the main README and delete it too.

## Keep

- **`Makefile` (`test`, `release`).** This is the documented entry point in both README and AGENTS.md, and it's tiny.
- **`scripts/fmt.sh` and its hook in `.claude/settings.json`.** It checks after every Write or Edit that `bfk/*.py` parses, and it works.
- **`scripts/run_tests.sh`.** It's the single source of the test command. If you want one fewer file, you could inline its one line into the Makefile and update AGENTS.md and the README. That's optional and a small gain.

## End state

You'd be left with a Makefile, one test script, the format hook in `.claude/settings.json`, and no `.mcp.json` config. That's two ways to run the tests and one way to release, and the release still asks before tagging.

Want me to make these deletions and update the README and AGENTS.md on a branch?
