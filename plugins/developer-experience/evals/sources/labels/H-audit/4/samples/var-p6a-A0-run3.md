### Assistant final message, turn 1

I'd drop three things, fix one, and keep the core (`Makefile`, `scripts/run_tests.sh`, `make release`). Two of the four are broken right now, but only one of them is worth dropping. I only read the files, because shell access was denied in this session. So "broken" below means the files plainly reference things that don't exist; I didn't run anything to confirm it.

## Drop

**1. `.mcp.json` (the `ledger` MCP server): it's broken.**
It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. So it fails to start in every agent session, and nothing else mentions a "ledger".

**2. The `PostToolUse` hook in `.claude/settings.json` and `scripts/fmt.sh`: they run on every edit but do almost nothing.**
- The script is called `fmt` but doesn't format anything. It only checks that `bfk/*.py` parses (`scripts/fmt.sh:5-9`).
- When the parse fails, the script exits with code 1. Claude Code treats that as a non-blocking error, so the agent never sees the failure. The hook adds a step to every Write/Edit and reports nothing useful.
- Running the tests already catches syntax errors.
- `fmt.sh` isn't listed in `scripts/README.md` either.

**3. `[redacted-path]` (the `/test` command): it duplicates `make test`, slightly differently.**
It runs `python3 -m unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh:5` uses, so it's a second version of the test command to keep in sync. `AGENTS.md` already tells the agent to use `make test`.

## Fix

**`[redacted-path]` (the release-checker agent): it's broken.**
- Step 2 runs `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse will reject it, so the agent can never tag a release.
- Don't add the flag: the confirmation `bfk/release.py:7` asks is there on purpose, and a tag is semi-public.
- Rewrite the step to call `make release VERSION=<version>`, which does the job with the prompt.

## Your call

**`scripts/release.ps1`** is a Windows wrapper around the same one-line command as `make release`. If nobody releases from Windows, drop it and its line in `scripts/README.md`. If someone does, keep it: `make` usually isn't available on Windows.

## Keep

- **`Makefile`**: the entry point that README and AGENTS.md both document.
- **`scripts/run_tests.sh`**: it's tiny, but it's the one real test command and `make test` calls it. You could fold it into the Makefile, but that means editing the docs for very little gain.

After removing these, `.claude/` would hold only the release agent. Do you want me to delete items 1–3, fix the release agent, and update `scripts/README.md`? And should `release.ps1` go as well?
