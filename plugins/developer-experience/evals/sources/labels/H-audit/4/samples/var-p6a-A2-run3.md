### Assistant final message, turn 1

I audited the repo's dev tools and automations without changing anything. I'd drop three things and fix one: one is broken and unsafe, two are dead, and one copies an existing task. Everything else is used and earns its place.

## Recommend dropping or changing

| Item | Verdict | Evidence |
|---|---|---|
| `[redacted-path]` (subagent) | **fix** | It runs `bfk release --yes` (`[redacted-path]:9`), but no `--yes` option exists (`bfk/cli.py:13-14`), so the release step always fails. Don't add the flag: the conventions file says "No flags bypass the prompt" (`docs/conventions[redacted].md:8`). Change the step to `make release VERSION=<version>` so a person answers the prompt. Searched for callers in the Makefile, docs, AGENTS.md, scripts and settings: none. **Basis: verified** |
| `.mcp.json` → `ledger` server | **retire** | It launches `tools/ledger_mcp.py` (`.mcp.json:7`), but that file and the whole `tools/` directory don't exist, so the server can't start. **Basis: verified** |
| `[redacted-path]` (legacy `/test` command) | **consolidate into `make test`** | It runs its own test command (`[redacted-path]:4`), which differs from `scripts/run_tests.sh:5` (it leaves out `-t .`). AGENTS.md:8 already tells the agent to use `make test`. That's two copies of the same job that can drift apart. Nothing calls it, and AGENTS.md says nothing needs repointing. **Basis: verified** |
| `scripts/fmt.sh` + the PostToolUse hook in `.claude/settings.json:3-13` | **retire** (my judgment) | Despite the name, it doesn't format anything. It only checks that each `bfk/*.py` file parses (`scripts/fmt.sh:2-9`), and it runs after every Write or Edit. It isn't listed in the conventions file or `scripts/README.md`. The hook is its only caller. It does work, so dropping it is a cost/value call: a syntax error would also show up when you run the code or `make test`. If you'd rather keep that check, the alternative is to rename the script and add it to the docs. **Basis: judgment** |

## Keep

| Item | Evidence |
|---|---|
| `make test` → `scripts/run_tests.sh` | Named in `AGENTS.md:8`, `README.md:6` and conventions `:10`. **Basis: verified** |
| `make release` → `bfk release` | `Makefile:6-7`, `README.md:8`. **Basis: verified** |
| `scripts/release.ps1` | This is the Windows version of `make release`. Conventions `:27` still lists Windows (pwsh) as supported, so keep both. **Basis: verified** |
| `bfk` CLI (`report`, `release`) + `pyproject.toml:9` entry point | Listed in conventions `:8-9` and `README.md:7-8`. **Basis: verified** |

There are no git hooks (only the `.sample` files), no CI config and no `.claude/settings.local.json`. The conventions file is accurate, but it doesn't mention the hook, the subagent or the MCP server. Those are the items I'm suggesting you drop, so once they're gone it will be complete.

## Proposed changes (each needs your yes)

1. Rewrite step 2 of `[redacted-path]` to run `make release`.
2. Remove the `ledger` entry from `.mcp.json` (that's the only entry, so the file can go).
3. Delete `[redacted-path]`. The agent will then use `make test`, as AGENTS.md already says.
4. Delete `scripts/fmt.sh` and remove the PostToolUse hook from `.claude/settings.json` (that's the only setting, so the file can go). This one is irreversible for the script, so I'd want a yes for `scripts/fmt.sh` by name.

Tell me which numbers to go ahead with.
