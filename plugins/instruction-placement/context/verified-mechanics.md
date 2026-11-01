# Verified loading mechanics: what actually happens, and how it was established

The evidence spine behind every routing decision this plugin makes. Read it before adjudicating a
candidate whose destination turns on *when* content loads, *whether it survives compaction*, or
*whether a subagent can see it*.

**Citation posture.** A claim marked *(doc MS-<n>)* is one this plugin relies on an official
Anthropic page for, and `MS-<n>` names its pointer record: the row in
[`mechanics-sources.tsv`](mechanics-sources.tsv) holding the section URL, the sentence quoted from
it that decides the claim, and the date it was read, with the recheck trigger under
[Pointer records](#pointer-records). The page is read there, not restated here.
*(changelog)* marks a claim that rests on a Claude Code release note alone, because
the docs page has not caught up with it; it names the release. *(measured)* marks what this
plugin's own first-party repro established, and *(inferred)* marks none of these. An inference is
never presented as any of the others. A
`measured` claim names the Claude Code version it was taken on, because these mechanics have moved
between releases and a version-less measurement cannot be re-verified or aged out.

## Contents

- [The surface table](#the-surface-table)
- [Pointer records](#pointer-records)
- [First-party measurements](#first-party-measurements)
- [Subagent visibility, re-measured on 2.1.268](#subagent-visibility-re-measured-on-21268)
- [Write and Edit inside a subagent, measured on 2.1.312](#write-and-edit-inside-a-subagent-measured-on-21312)
- [The three gaps that constrain the rubric](#the-three-gaps-that-constrain-the-rubric)
- [Glob semantics and their budgets](#glob-semantics-and-their-budgets)
- [Re-verification](#re-verification)

## The surface table

Every destination this plugin can route content to, priced by the three properties that decide
whether a move is safe.

| Surface | Enters context when | Survives compaction | Visible to a subagent |
|---|---|---|---|
| Root `CLAUDE.md` (cwd + ancestors) | Session start, in full *(doc MS-1, MS-29)* | Re-read from disk and re-injected *(doc MS-6, MS-8)* | **Yes** for general-purpose and custom subagents *(doc MS-12, measured 2.1.238)*; **No** for Explore, Plan, and an agent whose definition sets `omitClaudeMd`, which keeps only managed policy files, or none when its definition comes from managed settings *(doc MS-13)*; a fork inherits the parent conversation *(doc MS-14)* |
| `@import` from root `CLAUDE.md` | Session start, inlined *(doc MS-3)* | With its parent *(inferred)* | With its parent, so as the row above *(doc MS-3, MS-12, measured 2.1.238)* |
| Unscoped `.claude/rules/*.md` | Session start, priced as `.claude/CLAUDE.md` *(doc MS-4)* | Re-injected *(doc MS-8)* | **Yes**, with the same exceptions as root `CLAUDE.md` *(doc MS-12, MS-13)*; supersedes the **No** measured on 2.1.238 |
| Path-scoped rule (`paths:`) | When Read, Write or Edit targets a matching file, on 2.1.288 and later *(doc MS-5)*; on Read only before 2.1.288 *(changelog 2.1.288, measured 2.1.268)* | Reloads when a match recurs; compaction summarizes the earlier load away *(doc MS-7, MS-9)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)*, Explore, Plan and `omitClaudeMd` agents included *(doc MS-16)*, and on a matching Write or Edit there, after the tool runs *(measured 2.1.312)* |
| Nested `CLAUDE.md` | On Read, Write or Edit of another file in that subtree *(doc MS-2)*; Read measured *(measured 2.1.238)*; Write and Edit from 2.1.288 *(changelog 2.1.288, measured 2.1.312)* | Reloads when the subtree is touched again *(doc MS-7, MS-9)* | **Yes, on a matching read inside the subagent itself** *(measured 2.1.268)*, Explore, Plan and `omitClaudeMd` agents included *(doc MS-16)*, and on a Write or Edit there, after the tool runs *(measured 2.1.312)* |
| `@import` from a **nested** `CLAUDE.md` | With its parent, deferred *(measured 2.1.238)* | With its parent *(inferred)* | **Yes, with its parent, inside the subagent itself** *(measured 2.1.268)* |
| Bare nested `AGENTS.md` (no shim), with a `CLAUDE.md` on its path | **Never**, under the default **Project instructions** setting *(doc MS-17, MS-19, measured 2.1.238 and 2.1.278)* | n/a | No, it loads nowhere *(measured 2.1.238)* |
| Bare nested `AGENTS.md` (no shim), nothing on its path | On read of a file in that subtree, where AGENTS.md support is available *(doc MS-19, MS-20, MS-21, measured 2.1.278)*; the changelog (2.1.290) and the memory page differ on any other trigger *(source conflict, record below)* | Reloads when the subtree is touched again *(inferred from MS-7)* | Yes, on a matching read inside the subagent itself *(measured 2.1.278)* |
| Skill body | On invocation, then stays for the session *(doc MS-11)* | Invoked body re-injected within a per-skill and a total cap, oldest dropped first *(doc MS-10)*; the skill listing is rebuilt and re-injected on 2.1.304 and later *(doc MS-30)* | An invoked body is not inherited *(doc MS-15)*; one named in the agent's `skills` field is preloaded in full *(doc MS-31)*; any other is discovered and invoked through the Skill tool *(doc MS-32)* |

Each *(doc MS-<n>)* cell is a pointer, not a copy. When a routing decision turns on one, read the
record's quoted sentence at its URL; a page that no longer carries that sentence leaves the cell
unverified until the record and the cell are refreshed together.

The *(changelog)* markers rest on release notes, where no docs record can stand in:

- **Pointer**: for the Write and Edit trigger, the 2.1.288 entry of
  <https://code.claude.com/docs/en/changelog>, which dates the change the memory page states
  without a version (MS-2, MS-5); for what attaches a subdirectory `AGENTS.md`, fetch the 2.1.290
  entry of that changelog and record MS-19 live, since the two differ (source conflict) and a Read
  of an ordinary file there is the one trigger both support.
- **As of**: 2026-10-04; 2026-10-10 (the changelog side of the subdirectory `AGENTS.md` conflict,
  not re-read since; its docs side is MS-19, read on that record's date)
- **Recheck trigger**: the memory page's AGENTS.md section changes, or a release note names
  `AGENTS.md`, instruction-file loading, rules, subagent context, compaction, or what attaches a
  subdirectory `AGENTS.md`.

Three facts from that table carry the whole design:

- **An unscoped rule costs exactly what `CLAUDE.md` costs** (MS-4, MS-8). Moving a section from
  `CLAUDE.md` into `.claude/rules/` without `paths:` frontmatter saves nothing at all. The saving
  comes from the glob; the file move is bookkeeping.
- **A deferred surface does reach a subagent, but nothing is inherited.** The subagent starts
  without the parent's on-demand loads, and acquires a surface only by itself reading a path the
  surface covers. Delegation therefore does not put a demoted rule out of reach, but it does reset
  the trigger.
- **No deferred surface announces that it exists.** An agent working on something a rule covers,
  in any context, learns nothing about that rule until Claude works with a matching file. That is the
  residual the always-loaded index exists to close: the index supplies the knowledge, and an
  ordinary `Read` supplies the content.

## Pointer records

One record per docs claim this plugin prices a move by. The URL, the quoted sentence that decides
the claim, and the date it was read sit in that record's row of
[`mechanics-sources.tsv`](mechanics-sources.tsv) (columns `id`, `url`, `quote`, `as_of`), kept
machine-readable so a check can confirm each quote is still on its page. A quote is the sentence,
or the part of one that decides the claim, as the page renders it: link markup and bold dropped,
code spans kept, and a quote taken from a table joins its cells with ` | `.
This table holds what each record decides and when to recheck it.

| Record | Decides | Recheck when |
|---|---|---|
| MS-1 | Root `CLAUDE.md` and its ancestors load at session start | The memory page changes which directories load at launch |
| MS-2 | A nested `CLAUDE.md` loads on a Read, Write or Edit of another file in its subtree | That section changes the tool set that attaches a subdirectory `CLAUDE.md` |
| MS-3 | An `@import` loads with the file that imports it | The import section makes imports lazy or changes what they cost |
| MS-4 | An unscoped rule loads at session start, priced as `.claude/CLAUDE.md` | That sentence moves rules' priority or load time |
| MS-5 | A path-scoped rule loads on Read, Write or Edit of a matching file | That section adds or drops a triggering tool |
| MS-6 | Root `CLAUDE.md` is re-read from disk after `/compact` | The troubleshooting section changes what survives compaction |
| MS-7 | Nested `CLAUDE.md` and path-scoped rules return after compaction only on demand | As MS-6 |
| MS-8 | Root `CLAUDE.md` and unscoped rules are re-injected after compaction | That row of the compaction table changes |
| MS-9 | A deferred surface's earlier load is summarized away by compaction | That paragraph changes how deferred loads sit in history |
| MS-10 | Invoked skill bodies come back after compaction within a per-skill and a total cap | That row changes a cap or the drop order |
| MS-11 | A skill body enters on invocation and stays for the session | The skill-content-lifecycle section changes how a body persists |
| MS-12 | A non-fork subagent loads the main conversation's CLAUDE.md hierarchy, project rules and `AGENTS.md` included | The sub-agents page changes what that list carries |
| MS-13 | Explore, Plan and an `omitClaudeMd` agent skip it, keeping managed policy files at most, and none for a definition from managed settings | That page adds or removes an agent that skips the hierarchy, or changes what an `omitClaudeMd` agent keeps |
| MS-14 | A fork inherits the parent conversation | That page changes fork context |
| MS-15 | A subagent inherits none of the parent's invoked skills or read files | That page changes what a subagent inherits |
| MS-16 | A subagent that skips the hierarchy still loads deferred surfaces on its own file work | That sentence changes |
| MS-17 | A `CLAUDE.md` in the working directory or above shadows `AGENTS.md` by default | The AGENTS.md section changes the default |
| MS-18 | Which file names count as that shadowing `CLAUDE.md` | That list changes |
| MS-19 | A subdirectory `AGENTS.md` attaches on a Read there when the subdirectory has no `CLAUDE.md` of its own | That bullet changes the trigger or the condition; the 2.1.290 changelog conflict is resolved |
| MS-20 | Reading `AGENTS.md` directly needs Claude Code 2.1.277 or later | The floor moves |
| MS-21 | Some sessions read `CLAUDE.md` files only | The unavailable-support list changes |
| MS-22 | The brace-expansion budget: 1,000 patterns and 4 MiB across a rule's `paths:` list | The budget moves |
| MS-23 | An over-budget pattern is used unexpanded and matches nothing | That sentence changes the over-budget behavior |
| MS-24 | An unreadable `[` makes one pattern match nothing, the rest keep working | That sentence changes |
| MS-25 | `.claude/rules/` is discovered recursively | That sentence changes |
| MS-26 | User-level rules load before project rules | The order changes |
| MS-27 | A skill's listing entry is capped at 1,536 characters | The skills frontmatter table moves the cap |
| MS-28 | A skill's `paths:` limits its automatic loading to matching files | That row changes |
| MS-29 | A launch-loaded `CLAUDE.md` loads whole up to 4 MiB | The size limit moves |
| MS-30 | The skill listing is rebuilt and re-injected after compaction, from 2.1.304 | That row changes |
| MS-31 | A skill named in a subagent's `skills` field is preloaded in full | That bullet changes |
| MS-32 | A subagent discovers and invokes other skills through the Skill tool | That section changes what a subagent can reach without the `skills` field |
| MS-33 | A skill's `paths:` uses the rules' glob format | That row changes the format |
| MS-34 | A rule's `paths:` patterns are relative to its base directory | That section changes the base |

Recheck every record whenever a Claude Code release note names `AGENTS.md`, instruction-file
loading, rules, skills, subagent context or compaction, and refresh a row's `as_of` when its sentence is read
again, changed or not.

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
   observed the shadowing. The docs side of this finding is records MS-17 to MS-21.
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
**2.1.238** with the same canary method and now stand as *(measured 2.1.238)*.

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

- It covers the `Read` tool. Release 2.1.288 added the `Write` and `Edit` triggers after this run;
  [the 2.1.312 measurement](#write-and-edit-inside-a-subagent-measured-on-21312) covers them.
- It covers deferred surfaces. The **unscoped**-rule row rests on the sub-agents page instead
  (MS-12), which lists project rules among the CLAUDE.md files a non-fork subagent loads; this repository
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

## Write and Edit inside a subagent, measured on 2.1.312

**The repro.** A scratch git repository outside this checkout, with a root `CLAUDE.md`, two
path-scoped rules (`paths: ws/**` and `paths: es/**`), and nested `CLAUDE.md` files in `wn/` and
`en/`, each carrying a canary token. A throwaway settings file passed with `--settings` logged every
`InstructionsLoaded` payload, plus `PreToolUse` and `PostToolUse` for Read, Write and Edit. Two
headless runs each dispatched one general-purpose subagent: one wrote `ws/new.txt` and `wn/new.txt`
with no Read, the other edited the existing `es/target.txt` and `en/target.txt` with no Read.

1. **Write and Edit both fire both surfaces inside the subagent.** Each of the four tool calls was
   followed by one `InstructionsLoaded` record: `path_glob_match` for the rules, `nested_traversal`
   for the nested `CLAUDE.md` files, with `trigger_file_path` naming the written or edited file. No
   Read ran in either subagent.
2. **The load comes after the tool runs.** Each record follows that call's `PostToolUse`, and the
   subagent saw the canary in a system reminder after the Write or Edit result, never before it.
   This is what makes the write-trigger gap a timing gap.
3. **The records carry the subagent's identity.** Every load triggered in the subagent carried its
   `agent_id`, `agent_type: general-purpose` and `effort` (`{"level":"medium"}`); the main
   session's `session_start` loads carried none.

### Verification record

The rubric relies on what this probe observed on Claude Code 2.1.312: a Write or an Edit inside a
general-purpose subagent loads a matching path-scoped rule and a nested `CLAUDE.md` after the tool
runs, and the `InstructionsLoaded` record names the subagent.

- **Pointer**: the first-party probe above, two headless runs on the harness reported by
  `claude --version` as `2.1.312 (Claude Code)`, reported in
  <https://github.com/melodic-software/claude-code-plugins/issues/6758>.
- **As of**: 2026-10-27
- **Recheck trigger**: the consuming repository's Claude Code minor version moves past 2.1.312; or
  a release note touches the Write or Edit triggers, subagent context, or `InstructionsLoaded`
  input fields; or a real session observes a covered Write or Edit inside a subagent that injects
  nothing.

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
definition sets `omitClaudeMd` skip the project CLAUDE.md files and so never see the index
*(doc MS-13)*, though a deferred surface still reaches them on their own file work *(doc MS-16)*;
for them the gap stays open. The index guarantees **availability**, not
attention: injection is automatic and a pointer is discretionary. It therefore mitigates rather
than erases, which is why the hard-deny class below is not also delegated to it.

**The write-trigger gap.** Before 2.1.288 a path-scoped rule fired on a Read of a matching file and
on nothing else, so **creating a new file did not fire it** *(changelog 2.1.288)*. From 2.1.288 a
Write or Edit to a matching path fires it too *(doc MS-5)*. What
remains is timing: a `Write`-triggered rule arrives after the file is written *(measured 2.1.312)*,
too late to govern the creation it exists for. Content that governs the *creation* of files, such
as scaffolding templates, "every new component must…", and file-header requirements, is therefore
served badly by a path-scoped rule no matter how clean its glob looks: below 2.1.288 the rule
never fires on creation, and from 2.1.288 it fires after it. *Closed by:* routing
creation-governing content to a directory-nested surface or leaving it always-loaded, never to
`paths:`.

**The compaction gap.** The rubric prices compaction as bringing back the root `CLAUDE.md` and
leaving each deferred surface to return only when its trigger recurs *(doc MS-6, MS-7, MS-9)*. A
long session that compacts mid-task and then works
in a different subtree never re-loads what it demoted. *Closed by:* pricing this into every
recommendation, and by the hard-deny class for content whose absence is unrecoverable.

## Glob semantics and their budgets

The `check` skill (through `scripts/glob-tools.sh`) holds these as its own settings and enforces
each mechanically:

- Every `paths:` entry is a glob over repo-relative paths (MS-34), matched against tracked files.
- Brace groups multiply, and the check counts a rule's whole `paths:` list against the shared cap
  of MS-22. A pattern over the budget is reported `over-budget`, because Claude Code would use it
  unexpanded and its literal braces would match nothing (MS-23), a silent no-op rather than an
  error.
- A `[` the check cannot read as a bracket expression is reported `bad-bracket`, because that one
  pattern would match nothing while the rule's other patterns keep working (MS-24). The fix is an
  escaped literal, `\[`.
- The check walks `.claude/rules/` recursively (MS-25), so subdirectories are organizational. A
  user-level rule loads before a project rule (MS-26).

A glob that matches **zero** tracked files raises no error in Claude Code. The rule simply never
fires. That silence is exactly why `check` treats it as a failure.

## Re-verification

These mechanics are version-sensitive and have changed repeatedly across minor releases. Re-run the
measurements above when any of the following is true, and update the version stamp rather than the
claim's confidence:

- The consuming repo's Claude Code version has moved past the newest measurement here. This one
  is checked mechanically: `scripts/precompute.sh` compares `claude --version` with the newest
  version named after `measured` inside a citation marker, such as `*(measured 2.1.268)*`, and
  the `audit` and `realign` headers print `Mechanics record: STALE` when the CLI is newer. A
  measurement recorded without a version in its marker is invisible to that check, so stamp
  every new one there, and keep a stamped marker on one line with no parenthesis inside it: the
  check reads line by line and ends a marker at its first closing parenthesis.
- A finding here contradicts observed behavior in a real session.
- The official memory documentation changes its wording on deferral, imports, or subagent scope.

The repro is cheap: a temp git repo with canary tokens on each surface, an `InstructionsLoaded` hook
appending each payload to a log, one headless run that reads a file in the subtree, and a read of
the log. The repro relies on `InstructionsLoaded` being an observe-only event, so the measurement
does not perturb what it measures (see
<https://code.claude.com/docs/en/hooks#instructionsloaded>, as of 2026-10-01; recheck when that
section gives the event a decision control).
