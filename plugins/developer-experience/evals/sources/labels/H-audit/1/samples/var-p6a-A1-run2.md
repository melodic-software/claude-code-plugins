### Assistant final message, turn 1

I'd drop two things, fix one, slim down one more, and keep the rest. Bash was blocked in this session, so I read every file but couldn't run anything. The "broken" calls below come from reading the code.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It launches `python3 tools/ledger_mcp.py`, but there's no `tools/` directory, so the server fails to start in every session. Nothing else mentions a ledger.

**2. `[redacted-path]` (the `/test` command).** It's a second, different version of the test command: `python3 -m unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh` uses. Two versions will drift apart. AGENTS.md already tells the agent to use `make test`. If you'd rather keep `/test`, change its body to just "Run `make test`".

## Fix

**`[redacted-path]`.** The step is broken, not the idea:
- Step 2 runs `bfk.cli release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse would reject it with exit code 2, so the agent can't tag anything.
- Don't add the flag: AGENTS.md says "No flags bypass the prompt."
- Change step 2 to `make release VERSION=<version>` so a person still answers the prompt.

## Slim down

**3. Docs.** The same tool list appears in three places: AGENTS.md, README.md and `scripts/README.md`. I'd delete `scripts/README.md` and keep AGENTS.md as the full reference.

## Keep

- **`scripts/run_tests.sh` and `make test`:** this is the one real test entry point, and everything should route through it.
- **`make release` and `bfk release`:** the interactive confirmation is deliberate. `make release` with no `VERSION` gives an argparse usage error, which is ugly but harmless.
- **`scripts/fmt.sh` and its hook in `.claude/settings.json`:** it checks after every Write or Edit that `bfk/*.py` parses, and it works.
- **`scripts/release.ps1`:** AGENTS.md lists Windows (pwsh) as a supported platform, and `make` isn't available there.
- **`bfk` CLI (`bfk/cli.py`):** it's the product itself.
- **`bfk/proc.py`:** it's small, and it's the shared subprocess helper the conventions require.

One note outside dev tooling: the only tests cover `bfk/text.py:slugify`, which nothing in the CLI calls. Meanwhile `report` and `release` have no tests. That's worth a look later but isn't part of this cleanup.

I haven't changed anything. If you want, I can remove items 1 and 2, fix the release-checker step, and make the docs change (item 3), then update AGENTS.md and README.md to match in a single commit.
