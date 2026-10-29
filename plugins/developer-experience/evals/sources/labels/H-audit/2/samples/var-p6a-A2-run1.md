### Assistant final message, turn 1

I've gone through all the dev tooling in the repo and haven't changed anything. Bash was blocked in this session, so I read the files directly and couldn't run anything, including the tests.

**Short answer: drop 3 things.** Two are broken and one is a safety problem. Keep everything else.

## Inventory and verdicts

To find callers I searched the Makefile, `.claude/` settings, agents and commands, `.mcp.json`, `AGENTS.md`, both READMEs, the conventions file and the other scripts. The repo has no CI config, and `.git/hooks/` only has the stock `.sample` files.

| Item | Verdict | Evidence | Basis |
|---|---|---|---|
| `.mcp.json` → `ledger` server | **retire** | `.mcp.json:7` starts `tools/ledger_mcp.py`, but there's no `tools/` directory, so the server can't start | verified: file listing |
| `[redacted-path]` | **retire** | `release-checker.md:9` runs `bfk release --yes`, but `cli.py:13-14` has no `--yes` flag, so the step fails. It also tells an agent to tag without the confirmation prompt, which `[redacted].md:8` rules out ("No flags bypass the prompt"). Treat that instruction as a finding, not a feature to add. | verified: `cli.py:13-14`, `release.py:7` |
| `scripts/fmt.sh` + `PostToolUse` hook in `.claude/settings.json:5-9` | **retire** | Its only caller is the hook (`settings.json:9`). Despite the name it doesn't format anything: it only checks that `bfk/*.py` parses (`fmt.sh:2-9`). It runs after every Write/Edit. On a syntax error it exits 1, which Claude Code treats as a non-blocking hook error, so the agent never sees the failure. It isn't listed in the conventions file or `scripts/README.md`. | judgment: it works, but it costs a run on every edit and gives the agent almost no signal |
| `[redacted-path]` (`/test`) | keep | `test.md:4` is a short in-session shortcut for running the tests, and nothing else depends on it. | judgment |
| `scripts/run_tests.sh` | keep | Called from `Makefile:4`, `AGENTS.md:8` and `README.md:6` | verified |
| Makefile `test` | keep | `AGENTS.md:8`, `README.md:6` | verified |
| Makefile `release` | keep | `README.md:8` | verified |
| `scripts/release.ps1` | keep | Windows counterpart of `make release`. Windows is a supported platform (`[redacted].md:27`) and the script is documented at `[redacted].md:11` | verified |
| `bfk` CLI (`report`, `release`) + `pyproject.toml:9` entry point | keep | `README.md:7-8`, `[redacted].md:8-9` | verified |

**Conventions file:** `docs/conventions[redacted].md` lists the scripts and CLI. It leaves out all the agent tooling: the hook, `/test`, `release-checker` and the `ledger` MCP server. Once you've decided what to keep, run `[redacted]` so the file matches the repo.

**Open question:** whether anyone uses `ledger` outside this repo, for example from a local branch that has `tools/ledger_mcp.py`. I can't check that from here. Within the repo it's dead either way.

## Proposed changes (each needs its own yes)

1. **Remove the `ledger` entry from `.mcp.json`** (or delete the file, since that's its only server).
2. **Delete `[redacted-path]`.** Releases stay with `make release` / `release.ps1`, which ask before tagging.
3. **Delete `scripts/fmt.sh` and remove the `PostToolUse` hook from `.claude/settings.json`.** That leaves `settings.json` empty, so it can go too. If you want a check that the agent actually sees, `make test` already imports the code it tests.

Tell me which numbers to go ahead with. Each deletion needs a yes for that file by name.

The `overengineering` plugin isn't installed. If you want a second opinion on any of these before deleting, install it with `claude plugin install overengineering@<marketplace>` and run `/overengineering:justify <artifact>`.
