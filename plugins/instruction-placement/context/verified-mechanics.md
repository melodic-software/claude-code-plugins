# Verified loading mechanics: what actually happens, and how it was established

The evidence spine behind every routing decision this plugin makes. Read it before adjudicating a
candidate whose destination turns on *when* content loads, *whether it survives compaction*, or
*whether a subagent can see it*.

**Citation posture.** Claims are marked *(doc)* when an official Anthropic page states them,
*(measured)* when this plugin's own first-party repro established them, and *(inferred)* when
neither. An inference is never presented as either of the other two. A `measured` claim names the
Claude Code version it was taken on, because these mechanics have moved between releases and a
version-less measurement cannot be re-verified or aged out.

## Contents

- [The surface table](#the-surface-table)
- [First-party measurements](#first-party-measurements)
- [Subagent visibility, re-measured on 2.1.268](#subagent-visibility-re-measured-on-21268)
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
| Unscoped `.claude/rules/*.md` | Session start, "same priority as `.claude/CLAUDE.md`" *(doc)* | Re-injected *(doc)* | Unmeasured at 2.1.268; was **No** *(measured 2.1.238)* |
| Path-scoped rule (`paths:`) | On **read** of a matching file *(doc, measured)* | Re-injected when a match recurs *(doc)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)* |
| Nested `CLAUDE.md` | On read of a file in that subtree *(doc, measured)* | Reloads when the subtree is touched again *(doc)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)* |
| `@import` from a **nested** `CLAUDE.md` | With its parent, deferred *(measured)* | With its parent *(inferred)* | **Yes, with its parent, inside the subagent itself** *(measured 2.1.268)* |
| Bare nested `AGENTS.md` (no shim) | **Never** *(doc, measured)* | n/a | No, it loads nowhere *(measured 2.1.238)* |
| Skill body | On invocation *(doc)* | Listing re-injected; body on re-invoke *(doc)* | Discovered via the Skill tool *(doc)* |

Three facts from that table carry the whole design:

- **An unscoped rule costs exactly what `CLAUDE.md` costs.** Moving a section from `CLAUDE.md` into
  `.claude/rules/` without `paths:` frontmatter saves nothing at all. The glob is the product; the
  file move is bookkeeping.
- **A deferred surface does reach a subagent, but nothing is inherited.** The subagent starts
  without the parent's on-demand loads, and acquires a surface only by itself reading a path the
  surface covers. Delegation therefore does not put a demoted rule out of reach, but it does reset
  the trigger.
- **No deferred surface announces that it exists.** An agent working on something a rule covers,
  in any context, learns nothing about that rule until a read happens to match it. That is the
  residual the always-loaded index exists to close: the index supplies the knowledge, and an
  ordinary `Read` supplies the content.

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

Four findings follow, each of which a rubric rule depends on:

1. **An `@import` inside a *nested* `CLAUDE.md` defers with its parent.** `sub/AGENTS.md` loads with
   `load_reason: include` and carries its parent's `trigger_file_path`. It is absent at session
   start and arrives only when the subtree is touched. This is what makes the portable
   nested-`AGENTS.md` destination viable rather than a session-start cost in disguise.
2. **It is the opposite of the path-scoped-rule import case.** An `@import` inside a *path-scoped
   rule* inlines at session start and defeats the scoping. Both are "an import inside a deferred
   surface"; only one defers. Never generalize from one to the other. The rubric treats them as
   unrelated facts because measurement says they are.
3. **A nested `AGENTS.md` with no `CLAUDE.md` shim never loads.** `BARE_AGENTS_CANARY` was absent at
   session start and still absent after reading `bare/thing.txt`. The shim is a correctness
   requirement of the portable destination, not a stylistic nicety. This is what the docs mean by
   "Claude Code reads `CLAUDE.md`, not `AGENTS.md`" *(doc)*, confirmed to hold at every level of the
   tree, not only the root.
4. **A subagent inherits none of the parent's on-demand loads.** Dispatched *after* the parent had
   already loaded all five surfaces, a general-purpose subagent reported exactly
   `ROOT_CLAUDE_CANARY, ROOT_AGENTS_CANARY`. It inherited none of the parent's deferred loads.
   *This finding was originally written as "deferred surfaces do not load inside subagents at
   all", and that generalization is wrong: the run never had the subagent read a covered path, so
   it measured non-inheritance and not non-triggering.* See
   [Subagent visibility, re-measured on 2.1.268](#subagent-visibility-re-measured-on-21268), which
   supersedes the wider reading.

## Two claims this plugin makes, now measured

Both were asserted in 0.1.0 on documentation and inference. Both were re-run first-party on
**2.1.238** with the same canary method and now stand as *(measured)*.

- **An undocumented `description:` key in rule frontmatter is harmless.** A rule carrying both
  `description:` and `paths:` still loaded on a matching read. The index generator prefers that key
  over the H1, and this is why doing so is safe rather than merely likely-safe.
- **Block-level HTML comments are stripped from an `AGENTS.md` reached by `@import`.** The
  documentation states the stripping for CLAUDE.md files; this confirms it survives the import hop,
  which is what lets the generated index use HTML comment markers at zero context cost. A canary
  inside a comment was absent while the surrounding body was present.

## Subagent visibility, re-measured on 2.1.268

The 2.1.238 run measured what a subagent **inherits**, and this plugin read that as what a subagent
can **receive**. Those are different questions, and on **2.1.268** the second one answers the other
way: a deferred surface loads inside a subagent, on that subagent's own read.

**The repro.** A general-purpose subagent dispatched into this repository, which carries a
path-scoped rule globbing `**/*.py` (`.claude/rules/ruff-pin.md`) and a nested
`plugins/autonomy/CLAUDE.md` shim importing `plugins/autonomy/AGENTS.md`. No canary scaffolding is
needed: the surfaces arrive as a labelled `Contents of <repo-root>/<path>:` block appended to the
triggering tool result, so their presence is read straight off the transcript.

1. **Absent before the read.** At dispatch the subagent held the root `CLAUDE.md`/`AGENTS.md` pair
   only. Neither rule body was present, which reproduces finding 4's non-inheritance unchanged.
2. **Present after a matching read.** A `Read` of a `.py` path under `docs/specs/` returned with
   `Contents of <repo-root>/.claude/rules/ruff-pin.md:` and the rule's full body appended to the
   result. A `Read` of `plugins/autonomy/CLAUDE.md` likewise returned with
   `plugins/autonomy/AGENTS.md` appended, so the nested-shim `@import` hop defers and fires inside
   the subagent too.
3. **The match is on the requested path, not on a successful read.** The `.py` path used in step 2
   **did not exist**; the `Read` failed with `File does not exist` and the rule body was injected
   onto that failed result anyway. The glob is evaluated against the path the tool was *asked for*.

Two boundaries this measurement does **not** cross, stated so nothing generalizes past them:

- It covers the `Read` tool. It says nothing about whether a `Write` to a covered path that has
  never been read fires the same match, so the write-trigger gap below is unchanged.
- It covers deferred surfaces. Whether an **unscoped** rule reaches a subagent was measured only on
  2.1.238, and this repository has no unscoped rule to re-measure it with, so that table row is
  marked unmeasured rather than carried forward.

### Verification record

- **Claim.** On Claude Code 2.1.268, a path-scoped `.claude/rules/` file and a nested
  `CLAUDE.md`/`AGENTS.md` pair are injected inside a general-purpose subagent when that subagent
  reads a path the surface covers, and the glob matches the requested path whether or not the file
  exists. A subagent still inherits none of its parent's deferred loads.
- **Basis.** First-party probe run inside a subagent dispatched into this repository on the harness
  reported by `claude --version` as `2.1.268 (Claude Code)`, observing the `Contents of <path>:`
  blocks appended to `Read` results for one nonexistent `**/*.py` path and one existing
  `plugins/autonomy/CLAUDE.md`, against the rules and shims tracked at commit `49912c63`.
- **As of.** 2026-09-13.
- **Recheck trigger.** The consuming repository's Claude Code minor version moves past 2.1.268; or
  a Claude Code release note touches subagent context inheritance, memory loading, or path-scoped
  rule triggering; or a real session observes a covered `Read` inside a subagent that injects
  nothing. Any of these obliges re-running the three steps above and refreshing this record with
  the outcome, drift or no drift.

## The three gaps that constrain the rubric

Each gap is a place where a naive migration silently loses coverage. The rubric's hard rules exist
to close them; none of them is a reason not to migrate.

**The subagent gap.** Demoted content is not inherited by a non-fork subagent: the subagent starts
without every on-demand surface the parent had already loaded, and re-acquires one only by reading
a path that surface covers, inside its own context. So the gap is narrower than "invisible to
subagents" but it is real, and it has two live shapes. A worker briefed to edit files it has *not*
been told to read first can act before the governing rule ever fires; and any agent, in a subagent
or in the main session, that never touches a covered path is never told the rule exists at all.
*Closed by:* the always-loaded generated index, which is inherited (it is part of the root pair,
finding 4) and names every deferred surface, so an ordinary `Read` reaches its content from any
context. The index guarantees **availability**, not attention: injection is automatic and a pointer
is discretionary. It therefore mitigates rather than erases, which is why the hard-deny class below
is not also delegated to it.

**The write-trigger gap.** "Path-scoped rules trigger when Claude reads files matching the pattern,
not on every tool use" *(doc)*. Editing an existing file implies reading it, so the common case
holds; **creating a new file does not**. Content that governs the *creation* of files, such as
scaffolding templates, "every new component must…", and file-header requirements, is therefore
served badly by a path-scoped rule no matter how clean its glob looks. *Closed by:* routing creation-governing content
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
  literal braces match nothing, a silent no-op rather than an error.
- `[` opens a bracket expression. A `[` that cannot be read as one, as in `photos [2024/**`, makes
  that pattern match nothing while the rule's other patterns keep working. Escape a literal one as
  `photos \[2024/**`.
- Symlinked paths into the project directory match as of v2.1.198.
- Rules are discovered recursively under `.claude/rules/`, so subdirectories are organizational.
- User-level `~/.claude/rules/` load before project rules, giving project rules higher priority.

A glob that matches **zero** tracked files is not an error to Claude Code. The rule simply never
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
the log. `InstructionsLoaded` is observability-only and cannot block or modify a load, so the
measurement never perturbs what it measures.
