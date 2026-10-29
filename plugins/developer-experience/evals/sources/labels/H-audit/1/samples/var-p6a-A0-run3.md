### Assistant final message, turn 1

I'd drop two things, fix one, and keep the rest (`Makefile`, `scripts/run_tests.sh`, `make release`, the format hook, `scripts/release.ps1` and the `bfk` CLI). The ledger server and the release agent are broken right now. I only read the files, because shell access was denied in this session. So "broken" below means the files plainly reference things that don't exist; I didn't run anything to confirm it.

## Drop

**1. `.mcp.json` (the `ledger` MCP server): it's broken.**
It starts `python3 tools/ledger_mcp.py`, but there's no `tools/` directory in the repo. So it fails to start in every agent session, and nothing else mentions a "ledger".

**2. `[redacted-path]` (the `/test` command): it duplicates `make test`, slightly differently.**
It runs `python3 -m unittest discover -s tests` without the `-t .` that `scripts/run_tests.sh:5` uses, so it's a second version of the test command to keep in sync. `AGENTS.md` already tells the agent to use `make test`.

## Fix

**`[redacted-path]` (the release-checker agent): it's broken.**
- Step 2 runs `bfk release --yes <version>`, but `bfk/cli.py:13-14` has no `--yes` flag. argparse will reject it, so the agent can never tag a release.
- Don't add the flag: the confirmation `bfk/release.py:7` asks is there on purpose, and a tag is semi-public.
- Rewrite the step to call `make release VERSION=<version>`, which does the job with the prompt.

## Keep

- **`Makefile`**: the entry point that README and AGENTS.md both document.
- **`scripts/fmt.sh` and the `PostToolUse` hook**: they check after every Write or Edit that `bfk/*.py` parses, and they work.
- **`scripts/release.ps1`**: the Windows wrapper for `make release`, and `make` usually isn't available on Windows.
- **`bfk` CLI** (`bfk/cli.py`): the product itself, with `report` and `release`.
- **`scripts/run_tests.sh`**: it's tiny, but it's the one real test command and `make test` calls it. You could fold it into the Makefile, but that means editing the docs for very little gain.

After removing these, `.claude/` would hold only `settings.json` with the format hook and the fixed release agent. Do you want me to delete items 1–2 and fix the release agent?
