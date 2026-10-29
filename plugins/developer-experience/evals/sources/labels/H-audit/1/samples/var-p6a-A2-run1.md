### Assistant final message, turn 1

I've gone through all the dev tooling in the repo and haven't changed anything. Bash was blocked in this session, so I read the files directly and couldn't run anything, including the tests.

**Short answer: drop 2 things and fix 1.** One is broken, one duplicates `make test`, and one calls a flag that doesn't exist. Leave everything else as it is.

## Inventory and verdicts

To find callers I searched the Makefile, `.claude/` settings, agents and commands, `.mcp.json`, `AGENTS.md`, both READMEs, the conventions file and the other scripts. The repo has no CI config, and `.git/hooks/` only has the stock `.sample` files.

| Item | Verdict | Evidence | Basis |
|---|---|---|---|
| `.mcp.json` → `ledger` server | **delete** | `.mcp.json:7` starts `tools/ledger_mcp.py`, but there's no `tools/` directory, so the server can't start | verified: file listing |
| `[redacted-path]` | **fix** | `release-checker.md:9` runs `bfk release --yes`, but `cli.py:13-14` has no `--yes` flag, so the step fails. Don't add the flag: `[redacted].md:8` rules out bypassing the prompt ("No flags bypass the prompt"). Change the step to `make release VERSION=<version>` so a person still answers the confirmation in `release.py:7`. | verified: `cli.py:13-14`, `release.py:7` |
| `scripts/fmt.sh` + `PostToolUse` hook in `.claude/settings.json:5-9` | leave as is | Its only caller is the hook (`settings.json:9`). It checks that `bfk/*.py` parses (`fmt.sh:2-9`) after every Write/Edit, and it works. | verified |
| `[redacted-path]` (`/test`) | **merge** into `make test` | `test.md:4` repeats `run_tests.sh:5` but leaves out `-t .`, so the two can drift. It's also a legacy command file. Point it at `make test` or delete it. | judgment |
| `scripts/run_tests.sh` | keep | Called from `Makefile:4`, `AGENTS.md:8` and `README.md:6` | verified |
| Makefile `test` | keep | `AGENTS.md:8`, `README.md:6` | verified |
| Makefile `release` | keep | `README.md:8` | verified |
| `scripts/release.ps1` | keep | Windows counterpart of `make release`. Windows is a supported platform (`[redacted].md:27`) and the script is documented at `[redacted].md:11` | verified |
| `bfk` CLI (`report`, `release`) + `pyproject.toml:9` entry point | keep | `README.md:7-8`, `[redacted].md:8-9` | verified |

**Conventions file:** `docs/conventions[redacted].md` lists the scripts and CLI. It leaves out all the agent tooling: the hook, `/test`, `release-checker` and the `ledger` MCP server. Once you've decided what to keep, run `[redacted]` so the file matches the repo.

**Open question:** whether anyone uses `ledger` outside this repo, for example from a local branch that has `tools/ledger_mcp.py`. I can't check that from here. Within the repo it's dead either way.

## Proposed changes (each needs its own yes)

1. **Remove the `ledger` entry from `.mcp.json`** (or delete the file, since that's its only server).
2. **Rewrite the step in `[redacted-path]`.** Change `bfk release --yes` to `make release VERSION=<version>`, so the agent runs the release and a person still answers the prompt.
3. **Delete `[redacted-path]`.** `AGENTS.md:8` already points to `make test`. Alternatively, keep it and change line 4 to run `make test`.

Tell me which numbers to go ahead with. Each deletion needs a yes for that file by name.

The `overengineering` plugin isn't installed. If you want a second opinion on any of these before deleting, install it with `claude plugin install overengineering@<marketplace>` and run `/overengineering:justify <artifact>`.
