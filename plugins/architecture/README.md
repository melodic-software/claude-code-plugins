# architecture

A Claude Code plugin that scans an existing codebase for **module-level
architecture friction** and proposes concrete improvements. It is proactive
discovery, distinct from reviewing a diff or planning new work: it hunts for
shallow modules, seam leaks, and locality gaps in code that already exists. A
companion skill, `record-decision`, writes one architecture decision record into
whatever ADR convention the repository already has.

The first (and default) lens implements John Ousterhout's **deep-module**
concept from *A Philosophy of Software Design*. A module is *shallow* when its
interface is nearly as complex as its implementation, and *deep* when a small
interface hides large behavior. Deepening shallow modules improves both
testability and AI/agent-navigability: a small interface lets a reader grasp a
module's purpose without traversing the whole import graph.

## What it does

1. **Explore for friction.** Walks the codebase (via a read-only exploration
   subagent), reads the project's glossary and architecture decision records if
   present, and applies the *deletion test* to anything suspected shallow.
   Would deleting it concentrate complexity, or merely move it?
2. **Present candidates.** Writes a self-contained HTML report (inline styles and
   inline SVG only, no remote fetch) to the OS temp directory, one card per
   candidate with a before/after diagram, a recommendation badge, and a
   dependency-category badge. Alongside it, writes a durable machine-readable
   candidate list that survives the session.
3. **Interview the selected candidate.** Once you pick one, walks the decision tree
   covering constraints, dependencies, the shape of the deepened module, what sits
   behind the seam, and which tests survive, then records the agreed shape for a
   planning step to consume. When you want alternatives, a *Design-It-Twice*
   branch frames the problem space, fans out parallel subagents that each design
   the interface under a deliberately different constraint, compares the results
   on depth, locality, and seam placement, and closes with an opinionated
   recommendation.

## Across repositories

A second lens works one altitude up, over a *set* of repositories rather than
inside one codebase. `map-landscape` discovers the set, collects facts from a
tested script (owner, runtime, target framework, dependencies, last touched),
draws only the relationships a cited fact supports, and writes two artifacts
into the architecture directory your repository declares: a C4 System Landscape
view (Structurizr `systemLandscape`, or a mermaid `C4Context` block) and an
application-portfolio table. Anything no probe could derive stays `unknown`
rather than becoming a plausible guess.

Discovery is selected by argument. `--repos` charts exactly the repositories you
list. `--root` discovers, delegating to the `repo-fleet-hygiene` plugin when it
is installed and falling back to an announced bundled walk when it is not.
Neither argument stops and names both forms; the session's working directory is
never scanned.

## Record a decision

`/architecture:record-decision` discovers the ADR convention the repository
already uses (the directory, the numbering scheme, and the record shape) and
writes one record that follows it, reporting what it found before it writes.
Where nothing is declared and nothing exists, it names the rungs it searched,
offers two or three common shapes, and writes nothing at all until you pick one:
this plugin never prescribes a convention to a repository that has none. The
upstream template catalog is cited by URL for you to read, under its own
CC BY-NC-SA 4.0 licence; no template prose is copied into this plugin or into
your records.

## Invoke

```shell
/architecture:improve            # defaults to the deepening lens
/architecture:improve deepening  # explicit
/architecture:record-decision    # record one decision into the repo's convention

/architecture:map-landscape --repos /path/to/a,/path/to/b
/architecture:map-landscape --root /path/to/code-root

/architecture:setup check        # read-only: report the declaration state
/architecture:setup apply architecture_dir=docs/architecture
```

Trigger phrases (Claude may also invoke it automatically): "improve
architecture", "find deepening opportunities", "shallow modules", "architecture
scan", "make this more testable", "module seams", "locality", "map our
landscape", "system landscape", "what systems do we have", "application
portfolio", "who owns which repo", "chart our repositories".

## Consumer configuration

`map-landscape` reads two keys from a topic doc at your repository's convention
home, `<home>/architecture/README.md`: `architecture_dir` (repo-relative, no
default) and `landscape_dialect` (`structurizr` or `mermaid`, default
`mermaid`). The contract lives in [`reference/config.md`](reference/config.md).
`/architecture:setup` owns the declaration: `check` reports the state read-only,
`apply` converges the pointer region and the topic doc. With no
`architecture_dir` declared and none confirmed, `map-landscape` stops and points
at setup rather than choosing a directory for you.

## Persistence

The durable candidate list lands in the memory tier of the marketplace
topic-docs convention: `<memory_dir>/<topic-slug>/deepening-candidates-<timestamp>.md`,
default `.work/<topic-slug>/`. That path is never committed (the memory root
self-ignores), so scan output cannot leak into your git history. Resolution
honors your repo's `.claude/topic-docs.yaml` or declared working-docs
convention first (see `reference/topic-docs.md`); the skill reports the path
either way.

## Configuration

This plugin has no `userConfig`. It adapts to your project through your
project's own context: its glossary (if any), its architecture decision records,
and its work-artifact convention. There is nothing to hand-edit in the plugin.
The two `map-landscape` keys are consumer-side, not plugin-side; see Consumer
configuration above.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install architecture@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
