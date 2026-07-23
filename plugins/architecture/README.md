# architecture

A Claude Code plugin that scans an existing codebase for **module-level
architecture friction** and proposes concrete improvements. It is proactive
discovery, distinct from reviewing a diff or planning new work: it hunts for
shallow modules, seam leaks, and locality gaps in code that already exists.

The first (and default) lens implements John Ousterhout's **deep-module**
concept from *A Philosophy of Software Design* — a module is *shallow* when its
interface is nearly as complex as its implementation, and *deep* when a small
interface hides large behavior. Deepening shallow modules improves both
testability and AI/agent-navigability: a small interface lets a reader grasp a
module's purpose without traversing the whole import graph.

## What it does

1. **Explore for friction.** Walks the codebase (via a read-only exploration
   subagent), reads the project's glossary and architecture decision records if
   present, and applies the *deletion test* to anything suspected shallow —
   would deleting it concentrate complexity, or merely move it?
2. **Present candidates.** Writes a self-contained HTML report (inline styles and
   inline SVG only, no remote fetch) to the OS temp directory, one card per
   candidate with a before/after diagram, a recommendation badge, and a
   dependency-category badge. Alongside it, writes a durable machine-readable
   candidate list that survives the session.
3. **Interview the selected candidate.** Once you pick one, walks the decision tree
   — constraints, dependencies, the shape of the deepened module, what sits
   behind the seam, which tests survive — and records the agreed shape for a
   planning step to consume. When you want alternatives, a *Design-It-Twice*
   branch frames the problem space, fans out parallel subagents that each design
   the interface under a deliberately different constraint, compares the results
   on depth, locality, and seam placement, and closes with an opinionated
   recommendation.

## Invoke

```shell
/architecture:improve            # defaults to the deepening lens
/architecture:improve deepening  # explicit
```

Trigger phrases (Claude may also invoke it automatically): "improve
architecture", "find deepening opportunities", "shallow modules", "architecture
scan", "make this more testable", "module seams", "locality".

## Persistence

The durable candidate list is written to
`.claude/architecture/deepening-candidates-<timestamp>.md` in your project by
default. If
your project maintains its own per-task work-artifact convention (a tracked
working directory documented in your `CLAUDE.md` or rules), the skill honors that
location instead and reports the path either way.

## Configuration

This plugin has no `userConfig`. It adapts to your project through your
project's own context: its glossary (if any), its architecture decision records,
and its work-artifact convention. There is nothing to hand-edit in the plugin.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install architecture@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
