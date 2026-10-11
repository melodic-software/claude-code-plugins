# Agent-consumed surfaces: what loads, when, and how much

Read this when deciding how a file you are writing will actually reach an agent: whether it
auto-loads, at what moment, and under what size behavior. Write differently for an always-loaded
surface (every line is a per-session tax) than for an on-demand one (cost only when the trigger
fires).

The table sorts each surface into a load class: always loaded at session start, loaded on demand,
or loaded per invocation. That class is what changes how you write. Exact load order, size limits,
opt-in variables, version floors and per-surface conditions are upstream specifics; read them at the
pointers below the table when a write depends on one.

## Claude Code surfaces

| Surface | Path pattern | Load class |
|---------|-------------|---------------|
| Managed-policy CLAUDE.md / `claudeMd` key | OS-specific managed dirs | Session start; not excludable |
| User CLAUDE.md | `~/.claude/CLAUDE.md` | Session start |
| Project CLAUDE.md | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Session start; survives `/compact` |
| CLAUDE.local.md | `./CLAUDE.local.md` (also beside ancestor CLAUDE.md) | Session start |
| Ancestor CLAUDE.md | every dir from filesystem root down to cwd | Session start; excludable via `claudeMdExcludes` |
| Nested/subdirectory CLAUDE.md | `<subdir>/CLAUDE.md` below cwd | ON-DEMAND when Claude works with a file in that subdirectory (see [load triggers](#load-triggers)) |
| Project rules | `.claude/rules/**/*.md` | No `paths:` frontmatter → session start; with `paths:` globs → on-demand when Claude works with a matching file (see [load triggers](#load-triggers)) |
| User rules | `~/.claude/rules/*.md` | Session start, alongside project rules; we keep the two consistent rather than rely on either ranking above the other (see the user-rules pointer below) |
| `--add-dir` CLAUDE.md/rules | instruction files in each added directory | Session start only behind an opt-in; off by default |
| `@` imports | `@path` inside CLAUDE.md/rules | Expanded at launch with the importing file, so an import does NOT reduce context vs inlining |
| AGENTS.md | `AGENTS.md` and `.claude/AGENTS.md` in cwd and ancestors; nested: attaches lazily; see the source-conflict record in [load triggers](#load-triggers) | Session start, but whether it loads depends on a Project instructions setting and on which CLAUDE.md files sit at or above cwd: read both at the AGENTS.md pointer below. Availability moves; read it from the sources record behind `/instruction-placement:migrate` rather than from here. Where it does not load natively: only via `@AGENTS.md` import, symlink, `/init`, or `/import` |
| Auto-memory index | `MEMORY.md` in the auto-memory directory | Session start, head only; the excess is not loaded |
| Auto-memory topic files | same dir, `*.md` | On-demand only |
| Skills | `.claude/skills/`, `~/.claude/skills/`, plugin `skills/` | Listing metadata (description) in context every turn; body on invocation or model trigger |
| Commands (legacy) | `.claude/commands/`, `~/.claude/commands/` | On invocation; merged into the skills mechanism |
| Subagent definitions | `.claude/agents/`, `~/.claude/agents/`, plugin `agents/` | Per spawn: the body is the subagent's system prompt |
| Subagent persistent memory | `agent-memory/<agent>/` | Per spawn, head of that agent's MEMORY.md only |
| Output styles | `output-styles/` (user/project/managed/plugin) | Session start when selected; modifies the system prompt |
| Workflows | workflow directories (project, user, plugin) | Startup; each file becomes a command |
| Hook-carried instruction text | hooks in settings/plugins/frontmatter | On lifecycle events; output is size-capped, so keep it short |
| `--append-system-prompt` | CLI flag | Per invocation, appended to the default system prompt |
| `--append-system-prompt-file`, `--append-subagent-system-prompt`, `--append-subagent-system-prompt-file` | CLI flags | Per invocation; see [CLI prompt appends](#cli-prompt-appends) |

Load-semantics facts that change how you write:

- More specific scopes land later in context; we treat contradictions between scopes as a defect
  to remove, not a precedence to rely on (how scopes interact: the pointers below).
- Content that loads on demand (nested CLAUDE.md, `paths:`-gated rules) may be absent right after
  `/compact` until it loads again, so a constraint that must hold post-compaction belongs on a
  surface that survives it.
- Block-level HTML comments in CLAUDE.md are stripped before injection, which makes them free
  maintainer notes.
- MEMORY.md loads only its head, so put what must load first; keep CLAUDE.md short for adherence,
  and treat the 200-line target as ours to grade with (see `/docs-hygiene:audit-progressive-disclosure`).
- These surfaces are context, not enforcement, so a rule that must be mechanically guaranteed
  belongs in a hook or permission policy, not prose.

### Surface pointers

- **Pointer**: when a write depends on a load-order, exclusion, import or `--add-dir` detail, fetch
  <https://code.claude.com/docs/en/memory#how-claude-md-files-load>,
  <https://code.claude.com/docs/en/memory#load-from-additional-directories>,
  <https://code.claude.com/docs/en/memory#import-additional-files> and
  <https://code.claude.com/docs/en/memory#exclude-specific-claude-md-files> live; for user rules,
  <https://code.claude.com/docs/en/memory#user-level-rules>.
- **Pointer** (AGENTS.md load conditions and the setting that changes them):
  <https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md> and
  <https://code.claude.com/docs/en/memory#choose-which-instruction-files-load>.
- **Pointer** (auto-memory location, head limit, CLAUDE.md size handling):
  <https://code.claude.com/docs/en/memory#storage-location> and
  <https://code.claude.com/docs/en/memory#how-it-works>; subagent memory:
  <https://code.claude.com/docs/en/sub-agents#enable-persistent-memory>.
- **Pointer** (what survives compaction):
  <https://code.claude.com/docs/en/context-window#what-survives-compaction>.
- **Pointer** (other rows): subagent locations
  <https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope>; skill loading
  <https://code.claude.com/docs/en/skills#skill-content-lifecycle>; output styles
  <https://code.claude.com/docs/en/output-styles#create-a-custom-output-style>; workflows
  <https://code.claude.com/docs/en/workflows#save-the-workflow-for-reuse>; hook output caps
  <https://code.claude.com/docs/en/hooks#json-output>; system prompt flags
  <https://code.claude.com/docs/en/cli-reference#system-prompt-flags>.
- **As of**: 2026-10-11
- **Recheck trigger**: one of those sections changes a surface's load class, adds or removes a
  surface, or changes how rule scopes rank; the Project instructions setting is removed or its
  values change; or the compaction section changes which surfaces survive `/compact`.

### Load triggers

We describe nested CLAUDE.md and `paths:`-gated rules as loading when Claude works with a file they
cover, not only when it reads one, and we keep the list of tools and commands that count out of this
file.

- **Pointer**: when a placement depends on exactly which tool calls or shell commands trigger the
  load, fetch <https://code.claude.com/docs/en/memory#how-claude-md-files-load> (nested CLAUDE.md)
  and <https://code.claude.com/docs/en/memory#path-specific-rules> (path-scoped rules) live.
- **As of**: 2026-10-10
- **Recheck trigger**: the memory page changes the trigger list for either surface.

Source conflict: the changelog for v2.1.290 and the memory page's AGENTS.md section disagree on
what attaches a subdirectory AGENTS.md.

- **Pointer**: when a placement depends on what attaches a subdirectory AGENTS.md, fetch
  <https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md> and the v2.1.290 entry at
  <https://code.claude.com/docs/en/changelog#2-1-290> live.
- **As of**: 2026-10-10
- **Recheck trigger**: the memory page's AGENTS.md section changes what it says attaches a
  subdirectory AGENTS.md.

## CLI prompt appends

These are invocation flags, not memory files. Treat each as per-invocation instruction text: one
appends a file to the main system prompt, and two append text to subagent system prompts. Before
relying on one, read its mode restriction, version floor, fork exception and whether it combines
with its sibling at the pointer.

- **Pointer**: <https://code.claude.com/docs/en/cli-reference#cli-flags> (the three flag rows) and
  <https://code.claude.com/docs/en/cli-reference#system-prompt-flags> (how the flags combine).
- **As of**: 2026-10-11
- **Recheck trigger**: one of the three flag rows changes its mode restriction or leaves the table,
  or the System prompt flags section changes which flags combine.

Source conflict: the subagent file-flag row and the System prompt flags section disagree on whether
a flag combines with its own file form; read both before relying on either.

- **Pointer**: <https://code.claude.com/docs/en/cli-reference#cli-flags> and
  <https://code.claude.com/docs/en/cli-reference#system-prompt-flags>.
- **As of**: 2026-10-11
- **Recheck trigger**: either place changes what it says about combining a flag with its file form.

## Other-ecosystem analogues

For repos whose docs serve multiple agent harnesses. Names and auto-read semantics only;
verify a vendor's current behavior before relying on details.

| Convention | File(s) | Auto-read |
|---|---|---|
| AGENTS.md open standard | `AGENTS.md` root + nested (nearest wins) | Native in Codex, Cursor, Copilot agent, Gemini CLI (config), Windsurf, Zed, Roo, and in Claude Code under the conditions the Claude Code table above gives |
| Agent Skills standard (agentskills.io) | `<name>/SKILL.md` folders | Metadata-first progressive disclosure; discovery dirs per agent, where `.agents/skills/` + `~/.agents/skills/` is the shared cross-tool convention (Codex CLI, Cursor, Gemini CLI, VS Code Copilot, Zed); Claude Code uses its own `.claude/skills/` paths |
| Cursor rules | `.cursor/rules/*.mdc`; legacy `.cursorrules` | Per-rule types: Always / Auto Attached (globs) / Agent Requested / Manual |
| GitHub Copilot | `.github/copilot-instructions.md`; `.github/instructions/**.instructions.md` (`applyTo:` globs) | Auto-added to matching requests |
| Gemini CLI | `GEMINI.md` hierarchy + `~/.gemini/GEMINI.md` | Concatenated into every prompt |
| Windsurf | `.windsurf/rules/` (or `.devin/`); `global_rules.md` | Per-rule trigger modes |
| Cline / Roo | `.clinerules` file-or-folder / `.roo/rules/` | Appended to system prompt; workspace wins |
| Aider | `CONVENTIONS.md` | NOT auto-read; explicit `/read` / config only |
| JetBrains Junie | `.junie/guidelines.md` | Auto-read during generation |
| Amazon Q | `.amazonq/rules/*.md` | Auto-loaded on first interaction |
