### Assistant final message, turn 1

I'd drop four things, slim down one more, and keep the rest. Bash was blocked in this session, so I read every file but couldn't run anything. The "broken" calls below come from reading the code.

## Drop

**1. `.mcp.json` (the `ledger` MCP server).** It launches `python3 tools/ledger_mcp.py`, but there's no `tools/` directory, so the server fails to start in every session. Nothing else mentions a ledger.

**2. `[redacted-path]`.** It doesn't work, and it shouldn't:
- Step 2 runs `bfk.cli release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse would reject it with exit code 2, so the agent can't tag anything.
- Its stated purpose ("tag the release without the prompt") goes against AGENTS.md: "No flags bypass the prompt." Fixing it would mean adding the exact bypass the project rules out.
- What's left is "run tests, then tag", which is already `make test && make release VERSION=x` with a person answering the prompt.

**3. The `PostToolUse` hook in `.claude/settings.json`, plus `scripts/fmt.sh`.**
- Despite the name, `fmt.sh` doesn't format anything. It only checks that `bfk/*.py` parses, and it runs after every Write or Edit, including edits to Markdown or JSON.
- A syntax error makes Python exit with code 1. For a PostToolUse hook that is a non-blocking error, so the agent never gets the feedback. The check costs time on every edit and gives the agent nothing back.
- It also skips `tests/`, and `make test` imports the modules anyway, so a syntax error already shows up there. Neither README mentions `fmt.sh`.

**4. `[redacted-path]` (the `/test` command).** It's a second, different version of the test command: `python3 -m unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh` uses. Two versions will drift apart. AGENTS.md already tells the agent to use `make test`. If you'd rather keep `/test`, change its body to just "Run `make test`".

## Probably drop

**5. `scripts/release.ps1`.** It's a three-line wrapper around `python3 -m bfk.cli release $Version`, and `bfk release` already works the same way on Windows. It also calls `python3`, which often isn't on PATH on Windows (`py`/`python` are), so it may not even be the reliable path there. The one argument for keeping it is that AGENTS.md lists Windows (pwsh) as a supported platform. Documenting `python -m bfk.cli release <v>` for Windows would cover that with nothing extra to maintain.

## Slim down

**6. Docs.** The same tool list appears in three places: AGENTS.md, README.md and `scripts/README.md`. I'd delete `scripts/README.md` and keep AGENTS.md as the full reference. Once the items above are removed, also delete the `release.ps1` line from AGENTS.md.

## Keep

- **`scripts/run_tests.sh` and `make test`:** this is the one real test entry point, and everything should route through it.
- **`make release` (`Makefile`) and `bfk release` (`bfk/cli.py`):** the interactive confirmation is deliberate. `make release` with no `VERSION` gives an argparse usage error, which is ugly but harmless.
- **`bfk/proc.py`:** it's small, and it's the shared subprocess helper the conventions require.

One note outside dev tooling: the only tests cover `bfk/text.py:slugify`, which nothing in the CLI calls. Meanwhile `report` and `release` have no tests. That's worth a look later but isn't part of this cleanup.

I haven't changed anything. If you want, I can remove items 1–4 and 6 (and 5 if you agree) and update AGENTS.md and README.md to match in a single commit.
