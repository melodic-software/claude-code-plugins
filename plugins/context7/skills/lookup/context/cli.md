# CLI reference (`ctx7`)

Install, configure, command reference, flags, env vars, and Windows-specific gotchas.

> Verified 2026-11-03 against `ctx7` 0.9.0 (live `--help` output); first verified 2026-07-18
> against 0.5.5 and [Context7's CLI docs](https://context7.com/docs/clients/cli).
> The CLI moves fast. Re-check against a current install before acting on a row.

## Install

```bash
npm install -g ctx7@latest
ctx7 --version  # 0.6.0 or later
```

Fallback (no global install): `npx ctx7@latest <command>`. It is slower per invocation, but needs no PATH setup.

## Authentication

CLI works anonymously for low-rate usage. For higher limits, set the `CONTEXT7_API_KEY` env var:

```bash
export CONTEXT7_API_KEY="<your-key>"
```

Set it wherever your project manages local environment variables (shell profile, a gitignored local settings file, or your secret manager). Never commit the key.

**Prefer the env var over `ctx7 login`.** How `login` authenticates and where it keeps its token is [Context7 CLI § Authentication](https://context7.com/docs/clients/cli#authentication). The env-var approach is simpler, cross-machine-portable, and doesn't pollute the user profile. If `login` was run anyway, it's harmless but redundant. Delete `~/.ctx7/` to revert.

## Commands

| Command | Purpose |
|---|---|
| `ctx7 library <name> [query]` | Resolve library name to a Context7 library ID (the query argument is optional, but pass one: it drives ranking) |
| `ctx7 docs <libraryId> <query>` | Fetch documentation for a resolved library |
| `ctx7 search <query>` | An option, not the default (record below) |
| `ctx7 setup [flags]` | Configure Context7 for an IDE (this plugin does NOT use it, see below) |
| `ctx7 login` / `logout` / `whoami` | OAuth flow (this plugin does NOT use it, since the env var is enough) |
| `ctx7 remove` / `uninstall` | Remove a `setup`-installed agent configuration (this plugin does NOT use it) |
| `ctx7 upgrade` | Self-upgrade the CLI |

**This plugin does not use `ctx7 skills` or `ctx7 generate`,** and no behavior here depends on them.

- **Pointer**: for whether the CLI has either, run `ctx7 --help` and `ctx7 skills` on the installed
  CLI and fetch [upstash/context7#3425](https://github.com/upstash/context7/pull/3425) live.

**Lookups default to `ctx7 library`, then `ctx7 docs`; `ctx7 search` is an option.** The
selection, ambiguity-probe and version-specific-ID steps in [lookup.md](lookup.md) are built on
the two-step path, so it stays the default. Choose `search` for a question that spans several
libraries or names none, and only when the installed CLI's `ctx7 --help` lists it; otherwise use
the two steps.

- **Pointer**: when deciding whether `search` exists, what it does, which flags it takes and how
  its calls count, run `ctx7 --help` and `ctx7 search --help` on the installed CLI, and read
  [Search API or Context API?](https://context7.com/docs/search-api#search-api-or-context-api) and
  [Search API: Pricing](https://context7.com/docs/search-api#pricing) live.

## Flags

### Global

| Flag | Default | Purpose |
|---|---|---|
| `--base-url <url>` | `https://context7.com` | Point at a custom Context7 backend (API paths are appended) |
| `-v, --version` | | Print version |
| `-h, --help` | | Help for the current command |

### Per-command (`library`, `docs`)

| Flag | Purpose |
|---|---|
| `--json` | Structured JSON output (vs. formatted text). Useful for scripts / `jq` extraction |
| `--language <name>` | `docs` only: passed with the user's language when the installed CLI lists it; the probe and its pointer record are in [lookup.md](lookup.md#step-2-query-documentation) |

**For more content per call, prefer MCP.** Which flags `docs` takes is [Context7 CLI § Query Library Documentation](https://context7.com/docs/clients/cli#query-library-documentation). Use MCP (`mcp__context7__query-docs`); the measured ratio is in [mcp.md](mcp.md).

### Setup / install flags (why this plugin doesn't use them)

`ctx7 setup --claude --project --cli` installs Upstash's skills into `.claude/skills/`. **Never run it, and never run `ctx7 skills install` if a guide names it** (the record under [Commands](#commands) says where to check that command). This plugin does not use them because:

1. Installing creates a parallel `find-docs/` skill that fragments the lookup surface. This plugin owns the lookup workflow
2. An upstream-installed copy is not where this plugin keeps its customizations: the Windows gotcha notes, CLI-vs-MCP guidance, and action dispatch stay in this plugin
3. This plugin's `update` action ([update.md](update.md)) fetches upstream skill content for diffing, but integrates changes manually. A human reviews the merge

## Environment variables

| Variable | Purpose |
|---|---|
| `CONTEXT7_API_KEY` | Higher rate limits + priority |
| `CTX7_TELEMETRY_DISABLED` | Set to `1` to disable the CLI's anonymous usage telemetry |

Whether and what the CLI sends as telemetry is [Context7 CLI § Telemetry](https://context7.com/docs/clients/cli#telemetry). In privacy-sensitive environments, disable it per invocation (`CTX7_TELEMETRY_DISABLED=1 ctx7 docs ...`) or permanently by exporting the variable in your shell profile.

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
- No-op on macOS/Linux, so it is safe to always include
- Double-slash workaround (`//facebook/react`) does **not** work. ctx7 rejects it as malformed
- `ctx7 library` is unaffected (its first argument doesn't start with `/`)
- `ctx7 search --library /org/project` passes an argument starting with `/` too, so prefix it the
  same way; this follows from the same rewrite and has not been tested on Windows

This is a Git Bash quirk, not a `ctx7` bug. Any CLI taking `/org/project`-style IDs hits the same thing on Windows.

## Composability (CLI's main advantage over MCP)

Output goes to stdout in formatted text (with ANSI color codes) or JSON with `--json`. Common pipe patterns:

```bash
# Filter docs for a specific keyword
MSYS_NO_PATHCONV=1 ctx7 docs /facebook/react "hooks" | grep -A3 -i useEffect

# Strip ANSI for clean grep output
MSYS_NO_PATHCONV=1 ctx7 docs /facebook/react "hooks" | sed 's/\x1b\[[0-9;]*m//g' | grep useEffect

# Dump to disk (keeps context clean; echo the path in the same call — the docs
# output is redirected, so the path is the only thing the next Read can go on)
OUT=$(mktemp "${TMPDIR:-/tmp}/ctx7-XXXXXX"); echo "$OUT"; MSYS_NO_PATHCONV=1 ctx7 docs /vercel/next.js "app router" > "$OUT"

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

When not to: conversational lookups where the model picks the tool. MCP is more discoverable and returns more content. See [mcp.md](mcp.md) for that side.
