### Assistant final message, turn 1

Two of the repo's ten dev-tooling pieces can go and one needs a fix. Two are broken now, and one copies a command that already exists. I couldn't run anything (shell access was denied in this session), so everything below comes from reading the files.

## Drop

1. **`.mcp.json` (the `ledger` MCP server).** It launches `tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. Every session tries to start it and fails. Delete the file, or restore the script if someone still needs it.

2. **`[redacted-path]`.** This is a second copy of the test command and has already drifted from it: it runs `unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh` uses. `AGENTS.md` already tells the agent to use `make test`, so this is a second copy to keep in sync. Merge it into `make test` by cutting it down to "Run `make test` and report the result."

## Fix it

1. **`[redacted-path]`.** It's broken: it runs `bfk.cli release --yes <version>`, but `cli.py` has no `--yes` flag, so argparse will exit with an error and the agent can't do its job. Don't add the flag, because the "Tag release?" confirmation in `bfk/release.py:7` is the only safeguard on tagging. Rewrite the step to run `make release VERSION=<version>` so a person still answers the prompt.

## Keep

- **`Makefile` (`test`, `release`).** This is the documented entry point in both README and AGENTS.md, and it's tiny.
- **`scripts/fmt.sh` and its hook in `.claude/settings.json`.** Fine as is: it checks after every Write or Edit that `bfk/*.py` parses, and it works.
- **`scripts/release.ps1`.** Fine as is: it's the Windows entry point for `bfk release`, and `make` usually isn't available there.
- **`bfk` CLI (`bfk/cli.py`).** Still needed: it's the product itself.
- **`scripts/run_tests.sh`.** It's the single source of the test command. If you want one fewer file, you could inline its one line into the Makefile and update AGENTS.md and the README. That's optional and a small gain.

## End state

You'd be left with a Makefile, one test script, the format hook, the Windows wrapper, the fixed release agent, and no `.mcp.json` config. That's two ways to run the tests and one way to release, and the release still asks before tagging.

Want me to make these deletions and update the README and AGENTS.md on a branch?
