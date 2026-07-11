# CLI reference (`ctx7`)

Install, configure, command reference, flags, env vars, and Windows-specific gotchas.

## Install

```bash
npm install -g ctx7@latest
ctx7 --version  # 0.3.13 or later
```

Fallback (no global install): `npx ctx7@latest <command>` — slower per-invocation, no PATH ceremony.

## Authentication

CLI works anonymously for low-rate usage. For higher limits, set the `CONTEXT7_API_KEY` env var:

```bash
export CONTEXT7_API_KEY="<your-key>"
```

Set it wherever your project manages local environment variables (shell profile, a gitignored local settings file, or your secret manager) — never commit the key.

**Prefer the env var over `ctx7 login`** — `login` triggers browser OAuth and writes a token to `~/.ctx7/`. The env-var approach is simpler, cross-machine-portable, and doesn't pollute the user profile. If `login` was run anyway, it's harmless but redundant — delete `~/.ctx7/` to revert.

## Commands

| Command | Purpose |
|---|---|
| `ctx7 library <name> <query>` | Resolve library name → Context7 library ID |
| `ctx7 docs <libraryId> <query>` | Fetch documentation for a resolved library |
| `ctx7 setup [flags]` | Configure Context7 for an IDE (this plugin does NOT use it — see below) |
| `ctx7 login` / `logout` / `whoami` | OAuth flow (this plugin does NOT use it — env var is enough) |
| `ctx7 skills install <repo> [skill]` | Install skills from a GitHub repo (this plugin does NOT use it — see below) |
| `ctx7 skills search <keywords>` | Search the Context7 skills registry |
| `ctx7 skills suggest` | Auto-suggest skills based on project dependencies |
| `ctx7 skills info <repo>` | Show skills available in a repository |
| `ctx7 skills generate` | Interactive AI skill generator (Pro feature, requires login) |
| `ctx7 skills list` | List installed skills in the current directory |
| `ctx7 skills remove <name>` | Uninstall a skill |

Short aliases: `ctx7 skills` ↔ `ctx7 skill`, `install` ↔ `i`, `list` ↔ `ls`, `search` ↔ `s`, `generate` ↔ `gen/g`.

## Flags

### Global

| Flag | Default | Purpose |
|---|---|---|
| `--base-url <url>` | `https://context7.com/api` | Point at a custom Context7 backend |
| `-V, --version` | | Print version |
| `-h, --help` | | Help for the current command |

### Per-command (`library`, `docs`)

| Flag | Purpose |
|---|---|
| `--json` | Structured JSON output (vs. formatted text). Useful for scripts / `jq` extraction |

**No `--tokens`, `--limit`, `--format`, or `-v/--verbose` flag exists.** Default content depth is server-controlled. For more content per call, prefer MCP (`mcp__context7__query-docs`) — returns ~1.8× more content by default.

### Setup / install flags (why this plugin doesn't use them)

`ctx7 setup --claude --project --cli` and `ctx7 skills install /upstash/context7 find-docs --claude --yes` both install Upstash's skills into `.claude/skills/`. **This plugin does not use these** because:

1. They create a parallel `find-docs/` skill that fragments the lookup surface — this plugin owns the lookup workflow
2. `ctx7 skills install` re-fetched overwrites local customizations with zero warning — it would destroy the Windows gotcha notes, CLI-vs-MCP guidance, and action dispatch
3. This plugin's `update` action ([update.md](update.md)) fetches upstream skill content for diffing, but integrates changes manually — a human reviews the merge

## Environment variables

| Variable | Purpose |
|---|---|
| `CONTEXT7_API_KEY` | Higher rate limits + priority. Required for `ctx7 skills generate` |

The CLI reads no other env vars (no `CTX7_*` prefix detected in the compiled binary).

## Windows Git Bash gotcha (REQUIRED for `docs`)

On Windows with Git Bash / MSYS2, any CLI argument starting with `/` is rewritten to a Windows path. When you run:

```bash
ctx7 docs /facebook/react "useEffect cleanup"
```

Git Bash converts `/facebook/react` → `C:/Program Files/Git/facebook/react` before the CLI sees it. The CLI correctly rejects the malformed ID:

```text
✖ Invalid library ID: "C:/Program Files/Git/facebook/react"
```

**Always prefix `ctx7 docs` calls with `MSYS_NO_PATHCONV=1`:**

```bash
MSYS_NO_PATHCONV=1 ctx7 docs /facebook/react "useEffect cleanup"
```

- Prefix disables MSYS path conversion for that one invocation
- No-op on macOS/Linux — safe to always include
- Double-slash workaround (`//facebook/react`) does **not** work — ctx7 rejects it as malformed
- `ctx7 library` is unaffected (its first argument doesn't start with `/`)

This is a Git Bash quirk, not a `ctx7` bug. Any CLI taking `/org/project`-style IDs hits the same thing on Windows.

## Composability (CLI's main advantage over MCP)

Output goes to stdout in formatted text (with ANSI color codes) or JSON with `--json`. Common pipe patterns:

```bash
# Filter docs for a specific keyword
MSYS_NO_PATHCONV=1 ctx7 docs /facebook/react "hooks" | grep -A3 -i useEffect

# Strip ANSI for clean grep output
MSYS_NO_PATHCONV=1 ctx7 docs /facebook/react "hooks" | sed 's/\x1b\[[0-9;]*m//g' | grep useEffect

# Dump to disk (keeps context clean)
MSYS_NO_PATHCONV=1 ctx7 docs /vercel/next.js "app router" > /tmp/nextjs-router.md

# Extract library IDs from a search
ctx7 library react "hooks" --json | jq -r '.[0].id'

# Top 3 by benchmark score
ctx7 library "Entity Framework Core" "tracking" --json | jq 'sort_by(-.benchmarkScore) | .[0:3] | .[].id'
```

## When to prefer the CLI (summary)

- Pipe into `grep` / `jq` / `head` / a file
- Dump large docs to disk instead of context
- Scripting, loops, Bash one-liners
- No MCP server configured, or restricted networks where `mcp.context7.com` is blocked
- Structured extraction with `--json`

When not to: conversational lookups where the model picks the tool — MCP is more discoverable and returns more content. See [mcp.md](mcp.md) for that side.
