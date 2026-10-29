### Assistant final message, turn 1

I'd drop three things and keep the core (`Makefile`, `scripts/run_tests.sh`, `make release`). Two of the three are broken right now, so removing them costs nothing. I only read the files, because shell access was denied in this session. So "broken" below means the files plainly reference things that don't exist; I didn't run anything to confirm it.

## Drop

**1. `.mcp.json` (the `ledger` MCP server): it's broken.**
It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. So it fails to start in every agent session, and nothing else mentions a "ledger".

**2. `[redacted-path]`: it's broken, and its job is risky.**
- Step 2 runs `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse will reject it, so the agent can never tag a release.
- The agent exists to skip the confirmation prompt that `bfk/release.py:7` asks on purpose. A tag is semi-public and the agent can't undo it, so an agent shouldn't create one without a person confirming.
- `make release` already does the job, with the prompt.

**3. `[redacted-path]` (the `/test` command): it duplicates `make test`, slightly differently.**
It runs `python3 -m unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh:5` uses, so it's a second version of the test command to keep in sync. `AGENTS.md` already tells the agent to use `make test`.

## Your call

**`scripts/release.ps1`** is a Windows wrapper around the same one-line command as `make release`. If nobody releases from Windows, drop it and its line in `scripts/README.md`. If someone does, keep it: `make` usually isn't available on Windows.

## Keep

- **`Makefile`**: the entry point that README and AGENTS.md both document.
- **`scripts/fmt.sh` and the `PostToolUse` hook**: they check after every Write or Edit that `bfk/*.py` parses, and they work.
- **`scripts/run_tests.sh`**: it's tiny, but it's the one real test command and `make test` calls it. You could fold it into the Makefile, but that means editing the docs for very little gain.

After removing these, `.claude/` would hold only `settings.json` with the format hook. Do you want me to delete items 1–3 and update `scripts/README.md`? And should `release.ps1` go as well?
