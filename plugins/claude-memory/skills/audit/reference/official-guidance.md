# Official Claude Code Guidance on CLAUDE.md

## Contents

- [Size and adherence](#size-and-adherence)
- [Context injection clarification](#context-injection-clarification)
- [The deletion test](#the-deletion-test)
- [What to include vs exclude](#what-to-include-vs-exclude)
- [Build and test commands](#build-and-test-commands)
- [@import syntax](#import-syntax)
- [claudeMdExcludes setting](#claudemdexcludes-setting)
- [Skills vs CLAUDE.md](#skills-vs-claudemd)
- [Hooks vs CLAUDE.md](#hooks-vs-claudemd)
- [InstructionsLoaded hook](#instructionsloaded-hook)
- [Specificity](#specificity)
- [Consistency](#consistency)
- [Rules files](#rules-files)
- [Auto-memory limits](#auto-memory-limits)
- [Auto-memory storage](#auto-memory-storage)
- [Subagent persistent memory](#subagent-persistent-memory)
- [HTML comments](#html-comments)
- [Boris Cherny (CC creator)](#boris-cherny-cc-creator)
- [Style enforcement](#style-enforcement)
- [Compaction by steering method (June 2026)](#compaction-by-steering-method-june-2026)
- [No official scoring rubric](#no-official-scoring-rubric)

Each section states what this audit does, in our words, and points at the section of the official
page that covers the topic. Read the page there for its wording; this file stores none of it.

Last researched: 2026-06-20; the memory page pointers re-verified 2026-08-10 (the other sources
below were not re-checked on that date). Unless a section says otherwise, each pointer's as-of date
is 2026-06-20 and its recheck trigger is a Claude Code release note or docs change touching the
section it points at.

Refresh this file from current official docs via the skill's `update` action.

---

## Size and adherence

We flag a CLAUDE.md over 200 lines as an adherence risk, and treat a rule the model keeps ignoring
as a sign the file is too long. A third-party guide sets its own, looser line count; we use the
official target.

- **Pointer**: [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions),
  [My CLAUDE.md is too large](https://code.claude.com/docs/en/memory#my-claude-md-is-too-large),
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md);
  third-party: [humanlayer.dev, writing a good CLAUDE.md](https://humanlayer.dev/blog/writing-a-good-claude-md).

## Context injection clarification

We treat CLAUDE.md content as context the model reads, not enforced configuration and not part of
the system prompt, so a finding never promises strict compliance. Where an instruction must sit at
the system-prompt level, we point to `--append-system-prompt`.

- **Pointer**: [Troubleshoot memory issues](https://code.claude.com/docs/en/memory#troubleshoot-memory-issues),
  the "Claude isn't following my CLAUDE.md" entry.

## The deletion test

For each line, the audit asks whether removing it would make Claude make mistakes; a line that
fails the test is a cut candidate.

- **Pointer**: [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).

## What to include vs exclude

The audit keeps in CLAUDE.md what Claude cannot infer and that holds every session, and flags as
removal candidates what Claude can infer from the code or that changes often:

| Keep | Flag |
|---------|---------|
| Shell commands for this repo that the model would not work out | Facts the model can read off the code |
| Style choices that depart from the language's defaults | A language's ordinary conventions |
| How this repo runs its tests, and with which runner | Full API reference (link to it) |
| This repo's branch, commit and pull request habits | Facts that go stale quickly |
| Design decisions this project made | Tutorials and long background |
| Setup quirks of the dev environment, such as env vars it needs | A file-by-file tour of the codebase |
| Traps and surprising behavior | Advice any engineer already follows |

- **Pointer**: the include and exclude table in
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).

## Build and test commands

We expect a project CLAUDE.md to carry the build and test commands, because they lead the list of
what project memory is for and `/init` generates them. A project CLAUDE.md that omits them leaves
those commands to be discovered per session rather than read. Backs C9.

- **Pointer**: [Set up a project CLAUDE.md](https://code.claude.com/docs/en/memory#set-up-a-project-claude-md).

## @import syntax

The audit treats `@path/to/import` content as loaded at launch with the file that imports it, so an
import never saves context. Details the audit relies on:

- Relative and absolute paths both work; a relative path resolves from the importing file.
- Imports recurse, up to a maximum of 4 hops.
- An external import asks for approval the first time; a declined import stays disabled.
- Typical uses: README, package.json, personal preferences
  (`@~/.claude/my-project-instructions.md`).

- **Pointer**: [Import additional files](https://code.claude.com/docs/en/memory#import-additional-files).

## claudeMdExcludes setting

In a large monorepo, the audit recommends `claudeMdExcludes` to skip ancestor CLAUDE.md files that
do not apply:

```json
{
  "claudeMdExcludes": [
    "**/monorepo/CLAUDE.md",
    "<absolute-path>/other-team/.claude/rules/**"
  ]
}
```

- Patterns are globs matched against absolute file paths.
- Any settings layer may set it (user, project, local, managed policy); the audit combines every
  layer's patterns into one list.
- A managed policy CLAUDE.md cannot be excluded.

- **Pointer**: [Exclude specific CLAUDE.md files](https://code.claude.com/docs/en/memory#exclude-specific-claude-md-files).

## Skills vs CLAUDE.md

The audit recommends moving domain knowledge or workflows needed only sometimes out of CLAUDE.md
and unscoped rules into a skill, which loads on demand.

- **Pointer**: [Create skills](https://code.claude.com/docs/en/best-practices#create-skills),
  [Set up rules](https://code.claude.com/docs/en/memory#set-up-rules).

## Hooks vs CLAUDE.md

The audit recommends a hook, not a CLAUDE.md line, for anything that must happen every time: a
CLAUDE.md line is advisory and a hook is deterministic.

- **Pointer**: [Set up hooks](https://code.claude.com/docs/en/best-practices#set-up-hooks).

## InstructionsLoaded hook

To debug which instruction files load, when and why (path-scoped rules, lazy-loaded subdirectory
files), the audit points to the `InstructionsLoaded` hook. It only observes: it cannot block
loading or change content.

- **Pointer**: [`InstructionsLoaded`](https://code.claude.com/docs/en/hooks#instructionsloaded) and
  [Troubleshoot memory issues](https://code.claude.com/docs/en/memory#troubleshoot-memory-issues).

## Specificity

The audit flags an instruction too vague to verify (format code properly, test your changes, keep
files organized) and proposes a concrete one: an indentation width, a named test command, a named
directory.

- **Pointer**: [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions).

## Consistency

The audit flags two instructions that contradict each other across CLAUDE.md files, nested
CLAUDE.md files and `.claude/rules/`, since the model may pick either.

- **Pointer**: [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions)
  and [Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files).

## Rules files

The audit treats `.claude/rules/` as the place for modular instructions, and a path-scoped rule as
loading only after Claude reads a file its globs match. Features it relies on:

- Symlinks in `.claude/rules/` share rules across projects.
- User-level rules in `~/.claude/rules/` apply to every project and load before project rules.
- A path-specific rule uses `paths:` YAML frontmatter with glob patterns.

- **Pointer**: [Set up rules](https://code.claude.com/docs/en/memory#set-up-rules),
  [Path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules),
  [User-level rules](https://code.claude.com/docs/en/memory#user-level-rules).

**Path scoping status (verified working 2026-07-24 on Claude Code 2.1.219):** Path scoping defers as
documented. A path-scoped rule is not in context at session start and loads when Claude reads a
matching file. A first-party repro on 2.1.219 with `paths: ["**/*.tsx"]` found the rule absent at
session start, present after reading a matching `.tsx` file, and absent again after reading a
non-matching one: deferral works in both directions. No changelog entry or maintainer comment pins
the version where this began working, so do not claim a version floor. Recheck trigger: a Claude
Code release note or memory-doc change touching rule loading, or any session in which a path-scoped
rule is present at session start.

Caveats that do survive, each verified:

- An `@import` **inside** a path-scoped rule defeats the scoping: the imported content inlines at
  session start whether or not a matching file is ever read, since imports load at launch (pointer:
  [Import additional files](https://code.claude.com/docs/en/memory#import-additional-files)).
- Path-scoped content is not inherited by a subagent, and is invisible to teammates and
  skill-forked contexts. Issue #32906 covers this and is closed as not planned, so it is accepted
  behavior rather than a pending fix. Pointer: `gh api repos/anthropics/claude-code/issues/32906`,
  which returns `state: closed` and `state_reason: not_planned`. As of: 2026-09-06, Claude Code
  2.1.263. Recheck trigger: that issue reopens or closes as completed, or the memory page's
  subagent section changes.
- Non-inheritance is not unreachability: a subagent does receive a path-scoped rule once it reads
  a covered path itself. On Claude Code 2.1.268 a non-fork subagent inherits none of its parent's
  on-demand instruction surfaces, and receives a path-scoped `.claude/rules/` file, or a nested
  `CLAUDE.md` and the `AGENTS.md` its shim imports, when it reads a path that surface covers; the
  glob is matched against the requested path, so even a read that finds no file fires it.
  Pointer: our probe run inside a dispatched general-purpose subagent on the harness
  `claude --version` reports as `2.1.268 (Claude Code)`, observing the `Contents of <path>:` block
  appended to `Read` tool results. As of: 2026-09-13. Recheck trigger: the consuming repository's
  Claude Code minor version moves past 2.1.268, a release note names subagent context inheritance,
  memory loading, or path-scoped rule triggering, or a read of a covered path inside a subagent
  injects nothing.
- Writing a NEW file does not trigger the rule. We treat a read, not any tool use, as the trigger
  (pointer: [Path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules)).
- Excluding `project` from `--setting-sources` also drops the on-demand rules of both kinds:
  path-scoped ones, and those kept in a nested `.claude/rules/` (pointer:
  [Set up rules](https://code.claude.com/docs/en/memory#set-up-rules)).

## Auto-memory limits

The audit's size gate treats only the start of `MEMORY.md` as loaded at session start: 200 lines,
cut shorter when those lines pass 25KB. Everything after that is unread. The limit applies to
`MEMORY.md` only; a CLAUDE.md loads in full. The gate measures only the content that loads: YAML
frontmatter and block-level HTML comments are stripped first and do not count.

- **Pointer**: [How it works](https://code.claude.com/docs/en/memory#how-it-works) (auto memory).

## Auto-memory storage

The audit resolves the auto-memory directory as `~/.claude/projects/<project>/memory/`, with
`<project>` derived from the repository, so every worktree and subdirectory of one repository shares
one directory.

**`autoMemoryDirectory` setting:** overrides the default location; read from any settings scope:
user, project, local, policy, or `--settings`. From a project's `.claude/settings.json` or
`.claude/settings.local.json`, the value is honored only after the workspace trust dialog for that
folder is accepted (the same gate that governs hooks).

- **Pointer**: [Storage location](https://code.claude.com/docs/en/memory#storage-location).

## Subagent persistent memory

The audit treats a subagent's `memory` field as naming a directory that keeps its contents between
conversations, in one of three scopes:

| Scope | Location | Use when |
|-------|----------|----------|
| `user` | `~/.claude/agent-memory/<name>/` | Learnings across all projects |
| `project` | `.claude/agent-memory/<name>/` | Project-specific, shareable via version control |
| `local` | `.claude/agent-memory-local/<name>/` | Project-specific, not checked in |

- The same 200-line/25KB limit applies to a subagent's MEMORY.md.
- `project` is the default scope we recommend.
- Read, Write and Edit are enabled for memory management.

- **Pointer**: [Enable persistent memory](https://code.claude.com/docs/en/sub-agents#enable-persistent-memory).

## HTML comments

The audit treats block-level HTML comments in a CLAUDE.md as stripped before injection, so they are
the place for maintainer notes that spend no context; comments inside code blocks are kept. A
direct Read of the file still shows them.

- **Pointer**: [How CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load).

## Boris Cherny (CC creator)

Practices we take from Boris Cherny's published workflow, in our words:

- Add a CLAUDE.md line whenever Claude makes a mistake you do not want repeated.
- Keep editing CLAUDE.md until the mistake rate measurably drops.
- End a correction by asking Claude to update CLAUDE.md so the mistake is not repeated.
- **Auto-Dream (memory consolidation):** a subagent that reviews past sessions and consolidates
  what matters into cleaner memory.
- **`@.claude` PR tags:** `@.claude` tags in PR comments trigger CLAUDE.md updates during review.
- **Progressive disclosure for skills:** a skill is a folder, with SKILL.md as the hub and spoke
  files doing the work.

- **Pointer**: [howborisusesclaudecode.com](https://howborisusesclaudecode.com).

## Style enforcement

The audit flags a CLAUDE.md line that asks the model to do a linter's job and recommends a linter
or hook instead: a model is slower and costlier than a linter at that.

- **Pointer**: [humanlayer.dev, writing a good CLAUDE.md](https://humanlayer.dev/blog/writing-a-good-claude-md).

## Compaction by steering method (June 2026)

The audit models what survives `/compact` and what reloads on demand per destination as follows,
and prices a recommended move with that destination's row:

| Method | Session start | After compaction | On-demand trigger |
|--------|---------------|------------------|-------------------|
| CLAUDE.md | Full load | Project-root re-injected; nested reload on demand | Nested: file read in that subdirectory |
| Path-scoped rules | Matching paths only | Re-injected when paths match again | File read / edit |
| Unscoped rules | Full load | Re-injected | None |
| Skills | Name + description | Listing re-injected; body on invoke | `/skill` or model choice |
| Subagents | Name + description | Same as skills | Dispatch |
| Hooks | N/A (deterministic) | N/A | Every tool call |
| Auto-memory MEMORY.md | First 200 lines / 25KB | Persists on disk | None |
| Output style | If non-default | Persists for session | `/config` |

- **Pointer**: [Troubleshoot memory issues](https://code.claude.com/docs/en/memory#troubleshoot-memory-issues),
  the "Instructions seem lost after `/compact`" entry, and
  [Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle)
  (correlate with [Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)).

`AGENTS.md` is its own row's worth of behavior, and the row depends on the repository. The memory
page changed its `AGENTS.md` guidance between 2026-06-20 and 2026-09-19, so the row below is
derived from the page as of 2026-09-29, not from the earlier shim-only guidance.

The audit models an `AGENTS.md` as loading either directly, where no `CLAUDE.md`,
`.claude/CLAUDE.md` or `CLAUDE.local.md` in the working directory or above it displaces it and
`AGENTS.md` support is available, or through a `CLAUDE.md` that imports or symlinks it, on that
`CLAUDE.md`'s row. Read directly, it fires no `InstructionsLoaded` hook, and `/memory` lists it
from v2.1.280 (before that, `/memory` and `/context` did not); imported, it behaves as part of its
`CLAUDE.md`.

- **Pointer**: for when an `AGENTS.md` is read, when support is unavailable, and how it differs
  from `CLAUDE.md`, see [AGENTS.md](https://code.claude.com/docs/en/memory#agents-md),
  [When Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md),
  [When AGENTS.md support is unavailable](https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable),
  [Where AGENTS.md differs from CLAUDE.md](https://code.claude.com/docs/en/memory#where-agents-md-differs-from-claude-md)
  and the "My AGENTS.md isn't loading" entry under
  [Troubleshoot memory issues](https://code.claude.com/docs/en/memory#troubleshoot-memory-issues).
- **As of**: 2026-09-29
- **Recheck trigger**: those sections change which file names displace an `AGENTS.md` or which
  sessions lack support, the `/memory` listing or the difference table changes, or a release note
  names `AGENTS.md`.

## No official scoring rubric

We use no scoring rubric for CLAUDE.md quality, because no official one exists. The 6-category,
100-point rubric shipped by the `claude-md-improver` skill of the `claude-md-management` plugin
(Anthropic's `claude-plugins-official` marketplace, not this one) is invented by the plugin author,
not derived from official documentation.

The quality measure the audit uses is the [deletion test](#the-deletion-test).
