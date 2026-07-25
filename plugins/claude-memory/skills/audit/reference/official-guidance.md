# Official Claude Code Guidance on CLAUDE.md

Last researched: 2026-06-20
Sources: [Steering Claude Code (June 18, 2026)](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more), code.claude.com/docs/en/memory, code.claude.com/docs/en/hooks, code.claude.com/docs/en/best-practices, code.claude.com/docs/en/sub-agents, howborisusesclaudecode.com

Refresh this file from current official docs via the skill's `update` action.

---

## Size and adherence

> "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."
> — code.claude.com/docs/en/memory

<!-- -->

> "Files over 200 lines consume more context and may reduce adherence."
> — code.claude.com/docs/en/memory (troubleshooting section)

<!-- -->

> "Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"
> — code.claude.com/docs/en/best-practices

<!-- -->

> "Less than 300 lines is best, and shorter is even better."
> — humanlayer.dev/blog/writing-a-good-claude-md

<!-- -->

> "Frontier thinking LLMs can follow ~150-200 instructions with reasonable consistency."
> — humanlayer.dev/blog/writing-a-good-claude-md

## Context injection clarification

> "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself. Claude reads it and tries to follow it, but there's no guarantee of strict compliance, especially for vague or conflicting instructions."
> — code.claude.com/docs/en/memory (troubleshoot section)

<!-- -->

> "For instructions you want at the system prompt level, use `--append-system-prompt`."
> — code.claude.com/docs/en/memory

## The deletion test

> "Keep it concise. For each line, ask: 'Would removing this cause Claude to make mistakes?' If not, cut it."
> — code.claude.com/docs/en/best-practices

## What to include vs exclude

Official include/exclude table (code.claude.com/docs/en/best-practices):

| Include | Exclude |
|---------|---------|
| Bash commands Claude can't guess | Anything Claude can figure out by reading code |
| Code style rules that differ from defaults | Standard language conventions Claude already knows |
| Testing instructions and preferred test runners | Detailed API documentation (link to docs instead) |
| Repository etiquette (branch naming, PR conventions) | Information that changes frequently |
| Architectural decisions specific to your project | Long explanations or tutorials |
| Developer environment quirks (required env vars) | File-by-file descriptions of the codebase |
| Common gotchas or non-obvious behaviors | Self-evident practices like "write clean code" |

## @import syntax

> "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them."
> — code.claude.com/docs/en/memory

Key details:

- Both relative and absolute paths allowed. Relative paths resolve relative to the file containing the import
- Imported files can recursively import other files, max depth 5 hops
- First-time approval dialog for external imports; if declined, stays disabled
- Use for README, package.json, personal preferences (`@~/.claude/my-project-instructions.md`)

## claudeMdExcludes setting

> "In large monorepos, ancestor CLAUDE.md files may contain instructions that aren't relevant to your work. The `claudeMdExcludes` setting lets you skip specific files by path or glob pattern."
> — code.claude.com/docs/en/memory

```json
{
  "claudeMdExcludes": [
    "**/monorepo/CLAUDE.md",
    "<absolute-path>/other-team/.claude/rules/**"
  ]
}
```

- Patterns matched against absolute file paths using glob syntax
- Configurable at any settings layer (user, project, local, managed policy). Arrays merge across layers
- Managed policy CLAUDE.md cannot be excluded

## Skills vs CLAUDE.md

> "CLAUDE.md is loaded every session, so only include things that apply broadly. For domain knowledge or workflows that are only relevant sometimes, use skills instead. Claude loads them on demand without bloating every conversation."
> — code.claude.com/docs/en/best-practices

<!-- -->

> "Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use skills instead, which only load when you invoke them or when Claude determines they're relevant to your prompt."
> — code.claude.com/docs/en/memory (rules section)

## Hooks vs CLAUDE.md

> "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens."
> — code.claude.com/docs/en/best-practices

## InstructionsLoaded hook

> "Use the `InstructionsLoaded` hook to log exactly which instruction files are loaded, when they load, and why. This is useful for debugging path-specific rules or lazy-loaded files in subdirectories."
> — code.claude.com/docs/en/memory (troubleshoot section)

Observability-only — cannot block loading or modify content.

## Specificity

> "Write instructions that are concrete enough to verify."
> — code.claude.com/docs/en/memory

Official examples:

- "Use 2-space indentation" instead of "Format code properly"
- "Run `npm test` before committing" instead of "Test your changes"
- "API handlers live in `src/api/handlers/`" instead of "Keep files organized"

## Consistency

> "If two rules contradict each other, Claude may pick one arbitrarily. Review your CLAUDE.md files, nested CLAUDE.md files in subdirectories, and `.claude/rules/` periodically to remove outdated or conflicting instructions."
> — code.claude.com/docs/en/memory

## Rules files

> "For larger projects, you can organize instructions into multiple files using the `.claude/rules/` directory. This keeps instructions modular and easier for teams to maintain. Rules can also be scoped to specific file paths, so they only load into context when Claude works with matching files, reducing noise and saving context space."
> — code.claude.com/docs/en/memory

Additional features:

- Symlinks supported in `.claude/rules/` — maintain shared rules across projects
- User-level rules in `~/.claude/rules/` apply to every project (loaded before project rules)
- Path-specific rules use `paths:` YAML frontmatter with glob patterns

**Path scoping status (2026-04-01):** Official docs describe path scoping as working. In practice, issues #16299, #16853, #38487, #32906 remain open — rules load unconditionally at session start regardless of `paths:` frontmatter.

## Auto-memory limits

> "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation. Content beyond that threshold is not loaded at session start."
> — code.claude.com/docs/en/memory

<!-- -->

> "This limit applies only to `MEMORY.md`. CLAUDE.md files are loaded in full regardless of length, though shorter files produce better adherence."
> — code.claude.com/docs/en/memory

## Auto-memory storage

> "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`. The `<project>` path is derived from the git repository, so all worktrees and subdirectories within the same repo share one auto memory directory."
> — code.claude.com/docs/en/memory

**`autoMemoryDirectory` setting:** Override default location in user or local settings. Not accepted from project settings (security — prevents shared projects redirecting memory writes).

## Subagent persistent memory

> "The `memory` field gives the subagent a persistent directory that survives across conversations."
> — code.claude.com/docs/en/sub-agents

Three scopes:

| Scope | Location | Use when |
|-------|----------|----------|
| `user` | `~/.claude/agent-memory/<name>/` | Learnings across all projects |
| `project` | `.claude/agent-memory/<name>/` | Project-specific, shareable via version control |
| `local` | `.claude/agent-memory-local/<name>/` | Project-specific, not checked in |

- Same 200-line/25KB limit on subagent's MEMORY.md
- `project` is recommended default scope
- Read/Write/Edit tools auto-enabled for memory management

## HTML comments

> "Block-level HTML comments (`<!-- maintainer notes -->`) in CLAUDE.md files are stripped before the content is injected into Claude's context. Use them to leave notes for human maintainers without spending context tokens on them. Comments inside code blocks are preserved."
> — code.claude.com/docs/en/memory

When you open a CLAUDE.md file directly with the Read tool, comments remain visible.

## Boris Cherny (CC creator)

> "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md, so Claude knows not to do it next time."
> — howborisusesclaudecode.com

<!-- -->

> "Ruthlessly edit your CLAUDE.md over time. Keep iterating until Claude's mistake rate measurably drops."
> — howborisusesclaudecode.com

<!-- -->

> "End corrections with: 'Update your CLAUDE.md so you don't make that mistake again'"
> — howborisusesclaudecode.com

**Auto-Dream (memory consolidation):** Boris describes a subagent that "reviews past sessions, keeps what matters, removes what doesn't, and merges insights into cleaner structured memory."

**`@.claude` PR tags:** Use `@.claude` tags in PR comments to trigger automatic CLAUDE.md updates during code reviews.

**Progressive disclosure for skills:** "A skill is a folder, not a file. SKILL.md is the hub, spoke files do the work."

## Style enforcement

> "Never send an LLM to do a linter's job. LLMs are comparably expensive and incredibly slow."
> — humanlayer.dev/blog/writing-a-good-claude-md

## Compaction by steering method (June 2026)

Per [Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more) and [memory docs](https://code.claude.com/docs/en/memory) — what survives `/compact` vs what reloads on demand:

| Method | Session start | After compaction | On-demand trigger |
|--------|---------------|------------------|-------------------|
| CLAUDE.md | Full load | Project-root re-injected; nested reload on demand | Nested: file read in that subdirectory |
| Path-scoped rules | Matching paths only | Re-injected when paths match again | File read / edit |
| Unscoped rules | Full load | Re-injected | — |
| Skills | Name + description | Listing re-injected; body on invoke | `/skill` or model choice |
| Subagents | Name + description | Same as skills | Dispatch |
| Hooks | N/A (deterministic) | N/A | Every tool call |
| Auto-memory MEMORY.md | First 200 lines / 25KB | Persists on disk | — |
| Output style | If non-default | Persists for session | `/config` |

`AGENTS.md` is deliberately absent from that table: the memory doc's `AGENTS.md` section states
"Claude Code reads `CLAUDE.md`, not `AGENTS.md`", and prescribes an `@AGENTS.md` import or a symlink
as the way to make one load. So an `AGENTS.md` loads only through a `CLAUDE.md` that references it,
on that `CLAUDE.md`'s row — never as a surface of its own.

## No official scoring rubric

There is no official scoring rubric for CLAUDE.md quality. The `/claude-md-management:claude-md-improver` plugin's 6-category, 100-point rubric is invented by the plugin author, not derived from official documentation.

The official quality measure is the **deletion test**: "Would removing this cause Claude to make mistakes?"
