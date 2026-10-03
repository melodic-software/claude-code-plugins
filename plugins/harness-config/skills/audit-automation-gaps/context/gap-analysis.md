# audit-automation-gaps: per-category gap checklists

**Hooks**: For each language with production code (`.cs`, `.py`, `.ts`, `.sh`, `.ps1`, `.md`):

- Does a PostToolUse formatter hook exist?
- Does the language's build/lint tool run fast enough for a per-edit hook, judged against the consuming repo's own documented hook budget where it has one (see the skill's `context/hook-timing.md`)?
- Does a higher enforcement level (compiler, analyzer, build-time) already catch what the hook would catch?
- Does the need go past what a settings hook can do: draw in the interface (a pane, band, status entry or toast), register a command or tool, rewrite a prompt or model request, or read in-process session state? Then the candidate is a mod, a plugin of function hooks, and the verdict says so. Whoever writes it loads the built-in `plugin-authoring` skill first, because that skill carries the type declarations for the running Claude Code build.

**Claim:** which needs only a mod meets. **Basis:** the "Compare mods, settings hooks, skills, and MCP servers" table in the [mods overview](https://code.claude.com/docs/en/plugins/mods/overview), fetched as raw markdown, and the `plugin-authoring` skill's "From the ask to the shape" table for status entries, toasts and tools. **As of:** 2026-10-03, Claude Code 2.1.288. **Recheck:** either "Pick it when" cell for mods or settings hooks changes, or a release lets a settings hook draw in the interface.

**MCP Servers**: For each external service the repo interacts with:

- Is there an MCP server configured?
- Is there a CLI tool that already provides equivalent access?
- Is the service actually in use yet, or is it planned/future?

**Skills**: For each recurring workflow pattern:

- Is there a skill for it?
- How often does it occur? (check git history)
- Is there a simpler mechanism (CLI command, behavioral rule) that handles it?

**Subagents**: For each quality concern:

- Would a subagent provide value over a hook or skill?
- Does context isolation actually help?
- Is there a plugin that already provides this?

**Scheduled**: For each recurring maintenance task:

- Is it tracked in the repo's work-item tracker with a cadence?
- Does Dependabot or CI already handle it?
- Does a recurring-loop or scheduled-task mechanism provide the right durability model?
