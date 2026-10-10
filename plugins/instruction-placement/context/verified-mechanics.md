# Verified loading mechanics: what actually happens, and how it was established

The evidence spine behind every routing decision this plugin makes. Read it before adjudicating a
candidate whose destination turns on *when* content loads, *whether it survives compaction*, or
*whether a subagent can see it*.

**Citation posture.** A claim marked *(doc)* is one this plugin relies on an official Anthropic
page for; the page section is named in the pointer record beside it and is read there, not
restated here. *(changelog)* marks a claim that rests on a Claude Code release note alone, because
the docs page has not caught up with it; it names the release. *(measured)* marks what this
plugin's own first-party repro established, and *(inferred)* marks none of these. An inference is
never presented as any of the others. A
`measured` claim names the Claude Code version it was taken on, because these mechanics have moved
between releases and a version-less measurement cannot be re-verified or aged out.

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
| Root `CLAUDE.md` (cwd + ancestors) | Session start, in full *(doc)* | Re-read from disk and re-injected *(doc)* | **Yes** for general-purpose and custom subagents *(doc, measured)*; **No** for Explore, Plan, and an agent whose definition sets `omitClaudeMd` *(doc)*; a fork inherits the parent conversation *(doc)* |
| `@import` from root `CLAUDE.md` | Session start, inlined *(doc)* | With its parent *(inferred)* | With its parent, so as the row above *(doc, measured)* |
| Unscoped `.claude/rules/*.md` | Session start, priced as `.claude/CLAUDE.md` *(doc)* | Re-injected *(doc)* | **Yes**, with the same exceptions as root `CLAUDE.md` *(doc)*; supersedes the **No** measured on 2.1.238 |
| Path-scoped rule (`paths:`) | When Read, Write or Edit targets a matching file, on 2.1.288 and later *(doc)*; on Read only before 2.1.288 *(changelog 2.1.288, measured 2.1.268)* | Re-injected when a match recurs *(doc)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)*; Write and Edit inside a subagent unmeasured |
| Nested `CLAUDE.md` | On Read of a file in that subtree *(doc, measured)*; also when Write or Edit creates or changes a file there, on 2.1.288 and later *(changelog 2.1.288)* | Reloads when the subtree is touched again *(doc)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)*; Write and Edit inside a subagent unmeasured |
| `@import` from a **nested** `CLAUDE.md` | With its parent, deferred *(measured)* | With its parent *(inferred)* | **Yes, with its parent, inside the subagent itself** *(measured 2.1.268)* |
| Bare nested `AGENTS.md` (no shim), with a `CLAUDE.md` on its path | **Never** *(doc, measured 2.1.238 and 2.1.278)* | n/a | No, it loads nowhere *(measured 2.1.238)* |
| Bare nested `AGENTS.md` (no shim), nothing on its path | On read of a file in that subtree, where AGENTS.md support is available *(doc, measured 2.1.278)* | Reloads when the subtree is touched again *(doc)* | Yes, on a matching read inside the subagent itself *(measured 2.1.278)* |
| Skill body | On invocation *(doc)* | Invoked body re-injected within a per-skill and a total cap, oldest dropped first; the skill listing is not re-injected *(doc)* | Discovered via the Skill tool *(doc)* |

The plugin prices each instruction-file destination by the *(doc)* cells above and re-derives them
from the memory page, never from this table.

- **Pointer**: for when each instruction file loads, see
  <https://code.claude.com/docs/en/memory#how-claude-md-files-load>,
  <https://code.claude.com/docs/en/memory#set-up-rules>,
  <https://code.claude.com/docs/en/memory#path-specific-rules> and
  <https://code.claude.com/docs/en/memory#import-additional-files>; for what reloads after
  compaction, <https://code.claude.com/docs/en/memory#instructions-seem-lost-after-/compact> and
  <https://code.claude.com/docs/en/context-window#what-survives-compaction>; for the skill-body
  caps, that section and <https://code.claude.com/docs/en/skills#skill-content-lifecycle>; for
  what a subagent loads, <https://code.claude.com/docs/en/sub-agents#what-loads-at-startup> and its
  `omitClaudeMd` frontmatter field; for the Write and Edit trigger, the 2.1.288 entry of
  <https://code.claude.com/docs/en/changelog>, the only source for the nested `CLAUDE.md` half
  while the memory page still says "reads".
- **As of**: 2026-10-04
- **Recheck trigger**: any of those sections changes when a surface loads or reloads, or which
  subagents load the CLAUDE.md hierarchy; the memory page adopts or contradicts the 2.1.288 Write
  and Edit trigger for nested `CLAUDE.md`; or a release note names instruction-file loading, rules,
  subagent context, or compaction.

Three facts from that table carry the whole design:

- **An unscoped rule costs exactly what `CLAUDE.md` costs.** Moving a section from `CLAUDE.md` into
  `.claude/rules/` without `paths:` frontmatter saves nothing at all. The saving comes from the glob;
  the file move is bookkeeping.
- **A deferred surface does reach a subagent, but nothing is inherited.** The subagent starts
  without the parent's on-demand loads, and acquires a surface only by itself reading a path the
  surface covers. Delegation therefore does not put a demoted rule out of reach, but it does reset
  the trigger.
- **No deferred surface announces that it exists.** An agent working on something a rule covers,
  in any context, learns nothing about that rule until Claude works with a matching file. That is the
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
3. **A nested `AGENTS.md` with no `CLAUDE.md` shim never loads while a `CLAUDE.md` sits on its
   path.** `BARE_AGENTS_CANARY` was absent at session start and still absent after reading
   `bare/thing.txt`, in a repository whose root carried a `CLAUDE.md`. The shim is what loads the
   portable destination there, not a stylistic nicety. Re-measured on 2.1.278 the trigger is shared
   rather than exclusive: a nested `CLAUDE.md` and a nested `AGENTS.md` both attach on a Read in
   that directory, and what the root `CLAUDE.md` does is make Claude Code read `CLAUDE.md` files
   *instead of* `AGENTS.md`.
   The rubric treats an `AGENTS.md`, at the root or in a subdirectory, as shadowed wherever a
   `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` sits in the working directory or above
   it, and treats direct `AGENTS.md` reading as dependent on the CLI floor and session recorded in
   `skills/migrate/reference/sources.md`, "The minimum CLI version". Canary runs on 2.1.278
   observed the shadowing.
   - **Pointer**: for when Claude Code reads `AGENTS.md` and when that support is unavailable, see
     <https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md> and
     <https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable>.
   - **As of**: 2026-09-29
   - **Recheck trigger**: those sections change which file names shadow `AGENTS.md`, or a release
     note names `AGENTS.md` or instruction-file loading.
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
needed: the surfaces arrive as a labeled `Contents of <repo-root>/<path>:` block appended to the
triggering tool result, so their presence is read straight off the transcript.

1. **Absent before the read.** At dispatch the subagent held the root `CLAUDE.md`/`AGENTS.md` pair
   only. Neither rule body was present, which reproduces finding 4's non-inheritance unchanged.
2. **Present after a matching read.** A `Read` of a `.py` path the rule's glob covers returned with
   `Contents of <repo-root>/.claude/rules/ruff-pin.md:` and the rule's full body appended to the
   result. A `Read` of `plugins/autonomy/CLAUDE.md` likewise returned with
   `plugins/autonomy/AGENTS.md` appended, so the nested-shim `@import` hop defers and fires inside
   the subagent too.
3. **The match is on the requested path, not on a successful read.** The `.py` path used in step 2
   **did not exist**; the `Read` failed with `File does not exist` and the rule body was injected
   onto that failed result anyway. The glob is evaluated against the path the tool was *asked for*.

Two boundaries this measurement does **not** cross, stated so nothing generalizes past them:

- It covers the `Read` tool. Release 2.1.288 added the `Write` and `Edit` triggers after this run,
  so whether they fire inside a subagent, and when a `Write`-triggered surface arrives relative to
  the write, is not measured here; see the write-trigger gap below.
- It covers deferred surfaces. The **unscoped**-rule row rests on the sub-agents page instead,
  which lists project rules among the CLAUDE.md files a non-fork subagent loads; this repository
  has no unscoped rule to re-measure it with.

### Verification record

The rubric relies on what this probe observed on Claude Code 2.1.268: a path-scoped
`.claude/rules/` file and a nested `CLAUDE.md`/`AGENTS.md` pair are injected inside a
general-purpose subagent when that subagent reads a path the surface covers, the glob matches the
requested path whether or not the file exists, and a subagent still inherits none of its parent's
deferred loads.

- **Pointer**: the first-party probe above, run inside a subagent dispatched into this repository
  on the harness reported by `claude --version` as `2.1.268 (Claude Code)`, observing the
  `Contents of <path>:` blocks appended to `Read` results for one nonexistent `**/*.py` path and
  one existing `plugins/autonomy/CLAUDE.md`, against the rules and shims tracked at commit
  `49912c63`.
- **As of**: 2026-09-13
- **Recheck trigger**: the consuming repository's Claude Code minor version moves past 2.1.268; or
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
*Closed by:* the always-loaded generated index, which every subagent that loads the CLAUDE.md
hierarchy receives (it is part of the root pair, finding 4) and which names every deferred surface,
so an ordinary `Read` reaches its content from those contexts. Explore, Plan, and an agent whose
definition sets `omitClaudeMd` skip the project CLAUDE.md files and so never see the index *(doc; pointer in
the surface-table record)*; for them the gap stays open. The index guarantees **availability**, not
attention: injection is automatic and a pointer is discretionary. It therefore mitigates rather
than erases, which is why the hard-deny class below is not also delegated to it.

**The write-trigger gap.** Before 2.1.288 a path-scoped rule fired on a Read of a matching file and
on nothing else, so **creating a new file did not fire it** *(changelog 2.1.288)*. From 2.1.288 a
Write or Edit to a matching path fires it too *(doc; pointer in the surface-table record)*. What
remains is timing: the surfaces this plugin has observed arrive appended to the triggering tool
result, so a `Write`-triggered rule most likely arrives after the file is written *(inferred, not
measured)*, too late to govern the creation it exists for. Content that governs the *creation* of
files, such as scaffolding templates, "every new component must…", and file-header requirements,
is therefore still served badly by a path-scoped rule no matter how clean its glob looks, on any
CLI below 2.1.288 and, until the timing is measured, on 2.1.288 and later. *Closed by:* routing
creation-governing content to a directory-nested surface or leaving it always-loaded, never to
`paths:`.

**The compaction gap.** The rubric prices compaction as bringing back the root `CLAUDE.md` and
leaving each deferred surface to return only when its trigger recurs *(doc; pointer in the
surface-table record)*. A long session that compacts mid-task and then works
in a different subtree never re-loads what it demoted. *Closed by:* pricing this into every
recommendation, and by the hard-deny class for content whose absence is unrecoverable.

## Glob semantics and their budgets

The `check` skill (through `scripts/glob-tools.sh`) holds these as its own settings and enforces
each mechanically:

- Every `paths:` entry is a glob over repo-relative paths, matched against tracked files.
- Brace groups multiply, and the check counts a rule's whole `paths:` list against a shared cap:
  **1,000 expanded patterns, 4 MiB in total**. A pattern over the budget is reported `over-budget`,
  because Claude Code would use it unexpanded and its literal braces would match nothing, a silent
  no-op rather than an error.
- A `[` the check cannot read as a bracket expression is reported `bad-bracket`, because that one
  pattern would match nothing while the rule's other patterns keep working. The fix is an escaped
  literal, `\[`.
- The check walks `.claude/rules/` recursively, so subdirectories are organizational.

A glob that matches **zero** tracked files raises no error in Claude Code. The rule simply never
fires. That silence is exactly why `check` treats it as a failure.

- **Pointer**: for glob syntax, the brace-expansion budget, bracket expressions, recursive
  discovery and user-level rule order, see
  <https://code.claude.com/docs/en/memory#path-specific-rules>,
  <https://code.claude.com/docs/en/memory#set-up-rules> and
  <https://code.claude.com/docs/en/memory#user-level-rules>.
- **As of**: 2026-10-01
- **Recheck trigger**: that section moves the budget, changes how an unreadable `[` or an
  over-budget pattern behaves, or a release note names rule globs.

## Re-verification

These mechanics are version-sensitive and have changed repeatedly across minor releases. Re-run the
measurements above when any of the following is true, and update the version stamp rather than the
claim's confidence:

- The consuming repo's Claude Code major or minor version has moved.
- A finding here contradicts observed behavior in a real session.
- The official memory documentation changes its wording on deferral, imports, or subagent scope.

The repro is cheap: a temp git repo with canary tokens on each surface, an `InstructionsLoaded` hook
appending each payload to a log, one headless run that reads a file in the subtree, and a read of
the log. The repro relies on `InstructionsLoaded` being an observe-only event, so the measurement
does not perturb what it measures (see
<https://code.claude.com/docs/en/hooks#instructionsloaded>, as of 2026-10-01; recheck when that
section gives the event a decision control).
