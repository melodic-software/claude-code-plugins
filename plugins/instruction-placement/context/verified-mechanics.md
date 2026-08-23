# Verified loading mechanics — what actually happens, and how it was established

The evidence spine behind every routing decision this plugin makes. Read it before adjudicating a
candidate whose destination turns on *when* content loads, *whether it survives compaction*, or
*whether a subagent can see it*.

**Citation posture.** Claims are marked *(doc)* when an official Anthropic page states them,
*(measured)* when this plugin's own first-party repro established them, and *(inferred)* when
neither — an inference is never presented as either of the other two. A `measured` claim names the
Claude Code version it was taken on, because these mechanics have moved between releases and a
version-less measurement cannot be re-verified or aged out.

## Contents

- [The surface table](#the-surface-table)
- [First-party measurements](#first-party-measurements)
- [The three gaps that constrain the rubric](#the-three-gaps-that-constrain-the-rubric)
- [Glob semantics and their budgets](#glob-semantics-and-their-budgets)
- [Re-verification](#re-verification)

## The surface table

Every destination this plugin can route content to, priced by the three properties that decide
whether a move is safe.

| Surface | Enters context when | Survives compaction | Visible to a subagent |
|---|---|---|---|
| Root `CLAUDE.md` (cwd + ancestors) | Session start, in full *(doc)* | Re-read from disk and re-injected *(doc)* | **Yes** *(measured)* |
| `@import` from root `CLAUDE.md` | Session start, inlined *(doc)* | With its parent *(inferred)* | **Yes** *(measured)* |
| Unscoped `.claude/rules/*.md` | Session start, "same priority as `.claude/CLAUDE.md`" *(doc)* | Re-injected *(doc)* | **No** *(measured)* |
| Path-scoped rule (`paths:`) | On **read** of a matching file *(doc, measured)* | Re-injected when a match recurs *(doc)* | **No** *(measured)* |
| Nested `CLAUDE.md` | On read of a file in that subtree *(doc, measured)* | Reloads when the subtree is touched again *(doc)* | **No** *(measured)* |
| `@import` from a **nested** `CLAUDE.md` | With its parent, deferred *(measured)* | With its parent *(inferred)* | **No** *(measured)* |
| Bare nested `AGENTS.md` (no shim) | **Never** *(doc, measured)* | n/a | No *(measured)* |
| Skill body | On invocation *(doc)* | Listing re-injected; body on re-invoke *(doc)* | Discovered via the Skill tool *(doc)* |

Two rows carry the whole design:

- **An unscoped rule costs exactly what `CLAUDE.md` costs.** Moving a section from `CLAUDE.md` into
  `.claude/rules/` without `paths:` frontmatter saves nothing at all. The glob is the product; the
  file move is bookkeeping.
- **Everything that defers is invisible to subagents.** That is not a path-scoping quirk — it is
  every on-demand surface, which is why the always-loaded index exists.

## First-party measurements

Repro on **Claude Code 2.1.238**, a git repo with a root `CLAUDE.md` importing a root `AGENTS.md`,
a `sub/` holding a `CLAUDE.md` shim importing a `sub/AGENTS.md`, a `bare/` holding an `AGENTS.md`
with no shim, and a path-scoped rule globbing `sub/**/*.txt`. Each file carried a unique canary
token. An `InstructionsLoaded` hook recorded every load.

**Observed load records after reading `sub/thing.txt`:**

```json
{"file_path":"CLAUDE.md",              "memory_type":"Project","load_reason":"session_start"}
{"file_path":"AGENTS.md",              "memory_type":"Project","load_reason":"include","parent_file_path":"CLAUDE.md"}
{"file_path":"sub/CLAUDE.md",          "memory_type":"Project","load_reason":"nested_traversal","trigger_file_path":"sub/thing.txt"}
{"file_path":"sub/AGENTS.md",          "memory_type":"Project","load_reason":"include","parent_file_path":"sub/CLAUDE.md","trigger_file_path":"sub/thing.txt"}
{"file_path":".claude/rules/scoped.md","memory_type":"Project","load_reason":"path_glob_match","globs":["sub/**/*.txt"],"trigger_file_path":"sub/thing.txt"}
```

Four findings follow, each load-bearing somewhere in the rubric:

1. **An `@import` inside a *nested* `CLAUDE.md` defers with its parent.** `sub/AGENTS.md` loads with
   `load_reason: include` and carries its parent's `trigger_file_path` — it is absent at session
   start and arrives only when the subtree is touched. This is what makes the portable
   nested-`AGENTS.md` destination viable rather than a session-start cost in disguise.
2. **It is the opposite of the path-scoped-rule import case.** An `@import` inside a *path-scoped
   rule* inlines at session start and defeats the scoping. Both are "an import inside a deferred
   surface"; only one defers. Never generalize from one to the other — the rubric treats them as
   unrelated facts because measurement says they are.
3. **A nested `AGENTS.md` with no `CLAUDE.md` shim never loads.** `BARE_AGENTS_CANARY` was absent at
   session start and still absent after reading `bare/thing.txt`. The shim is a correctness
   requirement of the portable destination, not a stylistic nicety. This is what the docs mean by
   "Claude Code reads `CLAUDE.md`, not `AGENTS.md`" *(doc)*, confirmed to hold at every level of the
   tree, not only the root.
4. **A subagent saw only the root pair.** Dispatched *after* the parent had already loaded all five
   surfaces, a general-purpose subagent reported exactly `ROOT_CLAUDE_CANARY, ROOT_AGENTS_CANARY`.
   It inherited none of the parent's on-demand loads and re-triggered none of them.

## The three gaps that constrain the rubric

Each gap is a place where a naive migration silently loses coverage. The rubric's hard rules exist
to close them; none of them is a reason not to migrate.

**The subagent gap.** Demoted content is invisible inside every non-fork subagent. In a repo whose
work is routinely delegated — a reviewer agent, an implementer agent — demoting a convention can put
it out of reach of the exact agent that edits the files it governs. *Closed by:* the always-loaded
generated index, which reaches subagents (finding 4) and makes every rule reachable by an ordinary
`Read`. The index guarantees **availability**, not attention — injection is automatic, a pointer is
discretionary — so it mitigates rather than erases, which is why the hard-deny class below is not
also delegated to it.

**The write-trigger gap.** "Path-scoped rules trigger when Claude reads files matching the pattern,
not on every tool use" *(doc)*. Editing an existing file implies reading it, so the common case
holds; **creating a new file does not**. Content that governs the *creation* of files — scaffolding
templates, "every new component must…", file-header requirements — is therefore served badly by a
path-scoped rule no matter how clean its glob looks. *Closed by:* routing creation-governing content
to a directory-nested surface or leaving it always-loaded, never to `paths:`.

**The compaction gap.** Root `CLAUDE.md` is re-read from disk after `/compact`; deferred surfaces
return only when their trigger recurs *(doc)*. A long session that compacts mid-task and then works
in a different subtree never re-loads what it demoted. *Closed by:* pricing this into every
recommendation, and by the hard-deny class for content whose absence is unrecoverable.

## Glob semantics and their budgets

All *(doc)* unless marked. The `check` skill enforces each mechanically.

- Patterns are globs over repo-relative paths: `**/*.ts`, `src/**/*`, `*.md` (root only),
  `src/components/*.tsx`.
- Brace expansion is supported and multiplies: `src/*.{ts,tsx}` is two patterns,
  `{a,b}/{c,d}/*.{ts,tsx}` is eight. A rule's whole `paths:` list shares one budget of **1,000
  expanded patterns and 4 MiB**. A pattern exceeding the budget is used **unexpanded**, so its
  literal braces match nothing — a silent no-op, not an error.
- `[` opens a bracket expression. A `[` that cannot be read as one — `photos [2024/**` — makes that
  pattern match nothing while the rule's other patterns keep working. Escape a literal one as
  `photos \[2024/**`.
- Symlinked paths into the project directory match as of v2.1.198.
- Rules are discovered recursively under `.claude/rules/`, so subdirectories are organizational.
- User-level `~/.claude/rules/` load before project rules, giving project rules higher priority.

A glob that matches **zero** tracked files is not an error to Claude Code — the rule simply never
fires. That silence is exactly why `check` treats it as a failure.

## Re-verification

These mechanics are version-sensitive and have changed repeatedly across minor releases. Re-run the
measurements above when any of the following is true, and update the version stamp rather than the
claim's confidence:

- The consuming repo's Claude Code major or minor version has moved.
- A finding here contradicts observed behavior in a real session.
- The official memory documentation changes its wording on deferral, imports, or subagent scope.

The repro is cheap: a temp git repo with canary tokens on each surface, an `InstructionsLoaded` hook
appending each payload to a log, one headless run that reads a file in the subtree, and a read of
the log. `InstructionsLoaded` is observability-only — it cannot block or modify a load — so the
measurement never perturbs what it measures.
