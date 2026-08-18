# Agent-consumed surfaces — what loads, when, and how much

Read this when deciding how a file you are writing will actually reach an agent: whether it
auto-loads, at what moment, and under what size behavior. Write differently for an always-loaded
surface (every line is a per-session tax) than for an on-demand one (cost only when the trigger
fires).

Claude Code rows verified against official docs current at v2.1.233 (2026-08-17). The harness
releases frequently — when a load-timing detail is load-bearing for your write, re-verify it
against <https://code.claude.com/docs/en/memory> before relying on it.

## Claude Code surfaces

| Surface | Path pattern | When it loads |
|---------|-------------|---------------|
| Managed-policy CLAUDE.md / `claudeMd` key | OS-specific managed dirs | Session start, before all other scopes; cannot be excluded |
| User CLAUDE.md | `~/.claude/CLAUDE.md` | Session start, full |
| Project CLAUDE.md | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Session start; re-injected after `/compact` |
| CLAUDE.local.md | `./CLAUDE.local.md` (also beside ancestor CLAUDE.md) | Session start, after same-level CLAUDE.md |
| Ancestor CLAUDE.md | every dir from filesystem root down to cwd | Session start, root→cwd; excludable via `claudeMdExcludes` |
| Nested/subdirectory CLAUDE.md | `<subdir>/CLAUDE.md` below cwd | ON-DEMAND when the agent reads files there; NOT re-injected after `/compact` until the next matching read |
| Project rules | `.claude/rules/**/*.md` | No `paths:` frontmatter → session start; with `paths:` globs → on-demand on matching file read |
| User rules | `~/.claude/rules/*.md` | Session start, before project rules (lower priority) |
| `--add-dir` CLAUDE.md/rules | `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, `CLAUDE.local.md` in each added directory | Session start, ONLY when `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`; off by default — otherwise these files do not load at all |
| `@` imports | `@path` inside CLAUDE.md/rules; max 4 hops; skipped in code spans/fences | Expanded at launch with the importing file — an import does NOT reduce context vs inlining |
| AGENTS.md | not read natively | Only via `@AGENTS.md` import, symlink, `/init`, or `/import` |
| Auto-memory index | `~/.claude/projects/<project>/memory/MEMORY.md` | Session start: first 200 lines or 25KB, whichever first |
| Auto-memory topic files | same dir, `*.md` | On-demand only |
| Skills | `.claude/skills/`, `~/.claude/skills/`, plugin `skills/` | Listing metadata (description) in context every turn; body on invocation or model trigger |
| Commands (legacy) | `.claude/commands/`, `~/.claude/commands/` | On invocation; merged into the skills mechanism |
| Subagent definitions | `.claude/agents/`, `~/.claude/agents/`, plugin `agents/` | Body becomes the subagent's system prompt at spawn; description read at delegation time |
| Subagent persistent memory | `agent-memory/<agent>/` | First 200 lines/25KB of that agent's MEMORY.md at its spawn |
| Output styles | `output-styles/` (user/project/managed/plugin) | Session start when selected; modifies the system prompt |
| Workflows | `.claude/workflows/`, plugin `workflows/` | Startup; each file becomes a command |
| Hook-carried instruction text | hooks in settings/plugins/frontmatter | On lifecycle events; `additionalContext` capped at 10,000 chars |

Load-semantics facts that change how you write:

- Scope order is managed → user → project → local; the more specific scope lands later in
  context.
- Nested CLAUDE.md and `paths:`-gated rules do NOT survive `/compact` re-injection — a
  constraint that must hold post-compaction belongs on a surface that does.
- Block-level HTML comments in CLAUDE.md are stripped before injection — free maintainer notes.
- MEMORY.md hard-truncates (200 lines / 25KB); CLAUDE.md never truncates — official guidance is
  <200 lines per CLAUDE.md anyway.
- These surfaces are context, not enforcement — a rule that must be mechanically guaranteed
  belongs in a hook or permission policy, not prose.

## Other-ecosystem analogues

For repos whose docs serve multiple agent harnesses. Names and auto-read semantics only;
verify a vendor's current behavior before relying on details.

| Convention | File(s) | Auto-read |
|---|---|---|
| AGENTS.md open standard | `AGENTS.md` root + nested (nearest wins) | Native in Codex, Cursor, Copilot agent, Gemini CLI (config), Windsurf, Zed, Roo — not Claude Code |
| Agent Skills standard (agentskills.io) | `<name>/SKILL.md` folders | Metadata-first progressive disclosure; discovery dirs per agent — `.agents/skills/` + `~/.agents/skills/` is the shared cross-tool convention (Codex CLI, Cursor, Gemini CLI, VS Code Copilot, Zed); Claude Code uses its own `.claude/skills/` paths |
| Cursor rules | `.cursor/rules/*.mdc`; legacy `.cursorrules` | Per-rule types: Always / Auto Attached (globs) / Agent Requested / Manual |
| GitHub Copilot | `.github/copilot-instructions.md`; `.github/instructions/**.instructions.md` (`applyTo:` globs) | Auto-added to matching requests |
| Gemini CLI | `GEMINI.md` hierarchy + `~/.gemini/GEMINI.md` | Concatenated into every prompt |
| Windsurf | `.windsurf/rules/` (or `.devin/`); `global_rules.md` | Per-rule trigger modes |
| Cline / Roo | `.clinerules` file-or-folder / `.roo/rules/` | Appended to system prompt; workspace wins |
| Aider | `CONVENTIONS.md` | NOT auto-read — explicit `/read` / config only |
| JetBrains Junie | `.junie/guidelines.md` | Auto-read during generation |
| Amazon Q | `.amazonq/rules/*.md` | Auto-loaded on first interaction |
