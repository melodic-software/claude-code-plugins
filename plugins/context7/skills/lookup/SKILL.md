---
name: lookup
description: "Look up current library documentation, API references, and code examples via Context7 (ctx7 CLI or the Context7 MCP server — same backend) whenever a question names a library, framework, SDK, CLI tool, or cloud service, including API syntax, configuration, setup, and version-migration questions. Actions: lookup <library> <query> (default) | update (CLI upgrade + upstream drift check). For CLI/MCP setup, auth, and Windows gotchas, run /context7:setup."
argument-hint: "[lookup <library> <query> | update] (default: lookup — e.g., /context7:lookup react \"useEffect cleanup\")"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(ctx7 --version*)"
metadata:
  upstream-version: upstash/context7@master
  synced: 2026-05-22
  workflow-stage: research
  summary: Look up current library docs, API references, and examples via Context7
shell: bash
---

## Pre-computed context

Installed CLI version: !`ctx7 --version 2>/dev/null || echo "not installed (run: npm install -g ctx7@latest)"`

MCP availability: check your own tool list — if `mcp__context7__resolve-library-id` / `mcp__context7__query-docs` are present, the MCP path is configured.

## Purpose

A primary source of up-to-date library documentation. Two equivalent interfaces: CLI (`ctx7`) via npm, and the Context7 HTTP MCP server (`mcp__context7__*`) when the consuming project has it configured. Both read the same backend. Pick by workflow (see [When to use CLI vs MCP](#when-to-use-cli-vs-mcp)).

**Philosophy**: training data is stale by the time you use it. Library APIs, framework defaults, best practices change. Before claiming how a library works, verify against Context7 — even for libraries you "know."

## Actions

| Action | When | Loads |
|---|---|---|
| `lookup <library> <query>` (default) | User asks about a library | [context/lookup.md](context/lookup.md) |
| `update` | Drift check + CLI upgrade + upstream skill changes | [context/update.md](context/update.md) |

If the argument is bare (no action keyword), treat as `lookup`.

First-time setup — CLI install, `CONTEXT7_API_KEY` auth, optional MCP server wiring, and the Windows Git Bash gotcha — lives in its own skill: run `/context7:setup`.

## Lookup (happy path)

Two-step: resolve library name → fetch docs with resolved ID.

```bash
# Step 1: name → Context7 library ID
ctx7 library "<name>" "<question>"
# Step 2: ID → docs (Windows Git Bash: prefix with MSYS_NO_PATHCONV=1 — see context/cli.md)
MSYS_NO_PATHCONV=1 ctx7 docs "<libraryId>" "<question>"
```

Equivalent via MCP when the consuming project has the Context7 MCP server configured (no Windows gotcha, cleaner output, returns ~1.5-2× more content):

```text
mcp__context7__resolve-library-id(libraryName: "...", query: "...")
mcp__context7__query-docs(libraryId: "/org/project", query: "...")
```

You MUST call `library` / `resolve-library-id` first to get a valid ID, UNLESS the user provides one in `/org/project` format. One concept per query — when a question spans several independent topics, run a separate lookup per topic. Do not run more than 3 lookup commands per topic — if you cannot find what you need, fall back to training knowledge and tell the user Context7 didn't cover it.

**Do not include sensitive information** (API keys, passwords, credentials) in queries — sent to the Context7 backend.

Details: query-writing, result selection, version-specific IDs, common mistakes → [context/lookup.md](context/lookup.md)

## When to use CLI vs MCP

Both read the same backend — results equivalent in substance. Pick by workflow.

| Use the CLI (`ctx7`) when | Use the MCP (`mcp__context7__*`) when |
|---|---|
| Piping into `grep`, `jq`, `head`, a file | Conversational lookup where the model picks the tool naturally |
| Dumping large docs to disk (`> docs.md`) instead of context | Default docs depth matters (MCP returns ~1.8× more content per call) |
| Scripting, loops, Bash one-liners | Clean markdown output (no ANSI codes) |
| No MCP server configured, or `mcp.context7.com` blocked | Zero Windows Git Bash ceremony (no `MSYS_NO_PATHCONV=1`) |
| Structured extraction (`--json`) | Auto-discoverable from the model's tool list |

More: [context/cli.md](context/cli.md), [context/mcp.md](context/mcp.md)

## Update

Two upstream dependencies can drift: the `ctx7` npm package, and Upstash's reference skill content. Aggregate-level stale-tracking via `metadata.upstream-version` + `metadata.synced` in the frontmatter above; the verbatim upstream baselines under `vendor/` refresh together.

When CLI or upstream skill content drifts:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/lookup/scripts/update.sh"        # check only
bash "${CLAUDE_PLUGIN_ROOT}/skills/lookup/scripts/update.sh" --fix  # apply CLI upgrade
```

Script (a) reports installed vs latest `ctx7` version, (b) fetches latest upstream `find-docs/SKILL.md` and `context7-cli/SKILL.md` from `upstash/context7`, (c) diffs against the `vendor/` baselines, (d) if different, reports NEW upstream guidance for manual integration into this skill. The script does NOT auto-overwrite this `SKILL.md` — customizations (Windows gotcha, CLI-vs-MCP guidance, action dispatch) must be preserved.

Full protocol (merge strategy, what to preserve, maintainer-only baseline refresh) → [context/update.md](context/update.md)

## What this skill does NOT do

- **Does not replace multi-source research** — use your research workflow for architecture decisions or anything needing cross-referenced sources. This skill is library-doc retrieval only
- **Does not refactor code** — retrieves docs. User's question shapes what comes back
- **Does not cache content locally** — docs fetched fresh each call. `vendor/` baseline is verbatim upstream for skill-content drift detection only, not doc retrieval (do NOT read `vendor/` for normal lookup invocations; only when running the `update` action)
- **Does not auto-overwrite on update** — `update` is advisory. User approves any merge before changes land

## Gotchas

- **Windows Git Bash**: `ctx7 docs /org/project "..."` gets path-mangled to `C:/Program Files/Git/org/project`. Always prefix with `MSYS_NO_PATHCONV=1`. `ctx7 library` is unaffected. Full detail: [context/cli.md](context/cli.md)
- **Prefer the `CONTEXT7_API_KEY` env var over `ctx7 login`**: `ctx7 login` triggers browser OAuth and writes a token to `~/.ctx7/` — the env var is simpler and portable across machines. See [context/cli.md](context/cli.md)
- **No content tuning**: CLI has no `--tokens` / `--limit` flag. Default depth is server-controlled. For more content per call, prefer MCP (returns ~1.8× more by default)
- **Don't run `ctx7 skills install` into `.claude/skills/`**: this plugin owns the Context7 lookup surface. Installing Upstash's `find-docs` skill alongside creates a parallel surface that fragments lookups and drifts independently
