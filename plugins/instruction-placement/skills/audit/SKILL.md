---
description: "Read-only sweep for instruction content on the wrong surface: demote always-loaded conventions that belong on one file type or subtree; promote stranded docs conventions. Safety rails are hard-denied from demotion. Use when: 'my CLAUDE.md is too long', 'convert this to rules', 'what should be a path-scoped rule', 'move conventions to .claude/rules', 'find conventions in our docs', 'nested CLAUDE.md candidates', 'audit instruction placement'. Sibling realign applies accepted findings."
argument-hint: "[core|expanded] [path ...] [--repo <repo> ...]"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/quote-check.sh)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Read",
    "Grep",
    "Glob",
    "Write",
    "Skill",
  ]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Find instruction content on the wrong surface and propose validated destinations
---

**Arguments.** `[core|expanded] [path ...] [--repo <repo> ...]`. Default: core+expanded over the
whole repository. `--repo` and the other target forms: "Over several repositories" below

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" audit 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

Instruction content has a load cost set by the surface it sits on, and most repositories put
everything on the most expensive one. A convention that only matters when someone edits one kind of file
is paid for in every session, in every conversation, whether or not a file of that kind is touched.

**The saving is context, not obedience.** What the official guidance says about file length and
adherence is in
[Memory, "Write effective instructions"](https://code.claude.com/docs/en/memory#write-effective-instructions).
This plugin's own adherence measurement ([`../../evals/adherence-results.md`](../../evals/adherence-results.md))
does not reproduce a length effect on adherence for a clear, non-conflicting convention; the figures live in that file, and it is re-run
when the capability tier changes. So propose moves on context cost and on reaching content Claude
never loads, never by promising the operator their instructions will be followed better
afterwards.

This skill finds content whose scope is narrower than the surface carrying it, and content whose
surface Claude never reads at all, and proposes where each should go.

**It is read-only.** Every finding is a proposal; the operator decides, and `realign` executes.

## Over several repositories

With no target form, the run covers this checkout, as it always has. A target form selects several
repositories, resolved, counted and listed as
[`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](../../reference/target-scope.md) "Target forms"
and "Resolving repositories" say. What differs here:

- **Audit in the worktree `realign` will use.** The findings artifact is checkout-local and keyed by
  branch (`findings-artifact.md` "Where it lives"), so an artifact written in another checkout is
  one `realign` and `delta` never find. Per repository, that worktree is the one on the branch
  `instruction-placement/realign`, found in `git -C <root> worktree list --porcelain`. Reuse it
  when it exists, so a re-audit merges into the earlier artifact and keeps every decision. Only
  when none exists, create one on that branch by that repository's convention: from the local
  branch when it is left without a worktree, else from `origin/HEAD`. Run the workflow there, one
  subagent per repository ("Fan-out" there), with `--root` set to the worktree on every
  `detect.sh`, `glob-tools.sh` and `render-index.sh` call, the worktree's branch as the branch
  identity for the home, and that repository's own suppression surface. This worktree and branch
  are the only thing the audit adds to another repository; the read-only rule holds for every
  tracked file.
- **The quote check runs once.** It reads docs pages, not a repository: run it once, with no
  arguments, and pass its result into each repository's subagent brief.
- **One artifact per repository.** An `IP-<n>` handle is unique within its repository only, so the
  report writes every finding as `owner/name IP-<n>`.
- **One merged report.** Merge as "Merging findings" says, on this skill's rank (step 7 below).
  Name each repository's worktree path and artifact path, which `realign` and `delta` start from.
- **A rule several repositories repeat.** A section whose heading path and normative text match, or
  nearly match, in the always-loaded files of two or more repositories is one row of the merged
  report, listing each repository and source range. It names the candidate single homes: the
  machine layer (the user-scope instructions every repository's sessions load) and, when the
  operator names one, the standards repository. A section a sync mechanism already copies into
  each repository is excluded, as the contract's "Cross-repository signals" says. The row is
  report-only: it is written to no artifact, has no `finding_id`, `realign` never applies it, and
  it proposes no move or edit. Consolidating is the operator's own decision and edit, outside this
  plugin, so the boundary rule under "Hard rules" still holds.

## Read these before adjudicating anything

The judgment lives in the plugin's context files, not in this hub. Do not re-derive them. Open
each with the Read tool, one file per call, never through Bash `cat`.

| Read | For |
|---|---|
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | The hard-deny gate, the decision ladder, glob derivation, the promote lane |
| [`../../context/corpus.md`](../../context/corpus.md) | What is swept, in what order, and what is never touched |
| [`../../context/verified-mechanics.md`](../../context/verified-mechanics.md) | When each surface loads, and the three gaps that constrain every proposal |
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | The artifact's shape, location, and re-run merge semantics |

A proposal that contradicts `verified-mechanics.md` is wrong even if it looks like a saving. The
common one: moving a section into `.claude/rules/` *without* a `paths:` glob, which costs exactly
what it cost before.

## Check the mechanics quotes first

Each *(doc MS-<n>)* cell of the surface table in `verified-mechanics.md` rests on one sentence of a
live docs page. Before the detector runs, check that those sentences are still there:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/quote-check.sh"
```

It takes no arguments and fetches only the pages `${CLAUDE_PLUGIN_ROOT}/context/mechanics-sources.tsv` lists. It prints
one line per record: `verified <id>`; `drift <id> <url>`, with the stored and fetched sentences on
the next two lines; or `unverified <id> as of <date>` when the page could not be read fresh. It
exits 0 whatever the results, so a run with no network still completes. Its grant names the script
with no `*` (how such a rule matches:
<https://code.claude.com/docs/en/permissions#wildcard-patterns>).

A finding relies on the records its destination's row of the surface table cites. Carry the
results into the artifact and the summary:

- **Drift goes first.** Before any finding, list each `drift` result: the record id, its section
  URL, the stored wording and the fetched one. A finding that relies on a drifted record shows both
  wordings beside its destination, carries the unverified label below, and names the wording it is
  priced on.
- **Quote the deciding sentence.** Write each record a finding relies on into its `Mechanics`
  field as `MS-<n> <result>: "<quote>"`, the quote from the record's `quote` column.
- **Label what was not read.** A finding that relies on an `unverified` or a drifted record is
  labeled "unverified as of <date>", in the artifact and in the summary. The date is the one the
  `unverified` line printed, or for a drifted record its `as_of` in the list. The label changes no
  rank; it shows the operator which proposals rest on a stored quote alone.

## The two lanes

**Demote**. Content already in the instruction layer, sitting higher than its scope warrants. The
saving is real but so is the trade: what defers is absent until a read matches it, absent again
after a compaction until that trigger recurs, never inherited by a subagent, and never announced,
so nothing tells an agent it exists. Price it, every time.

**Promote**. Normative content in ordinary documentation that Claude loads *never*. There is no
presence to lose, so the gaps do not apply and any working destination is a strict improvement. The
live risk here is duplication, not context: resolve single-source-of-truth per candidate using the
rubric's table rather than reflexively copying.

## Facts before judgment

Run the detector after the quote check and build every finding on what it emits:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh" [--tier core]
```

It emits deterministic TSV and adjudicates nothing:

| Record | Carries | Used for |
|---|---|---|
| `FILE` | path, corpus tier, line count | Corpus accounting, and the coverage report |
| `SECTION` | path, **start**, **end**, level, heading | Candidate boundaries and their line ranges |
| `SIGNAL` | path, section start, normative hit count, markers | The promote lane's normative bar |
| `HINT` | path, section start, `ext`/`dir`/`lang`, value | Raw material for glob derivation |
| `RULE` | path, `scoped`/`unscoped`, globs | Existing rule inventory, and re-scope candidates |
| `SKIP` | path, reason | The honest coverage report |

**Cite the detector's line ranges verbatim.** `realign` excises by the range the finding carries, so
a range you inferred by reading is a guess that removes the wrong text. If a candidate does not
correspond to a `SECTION` record, say so rather than inventing a boundary.

**A `HINT` is raw material, not a decision.** The detector reports what the text literally says; it
does not know whether an extension it names is the candidate's real scope. Derive the glob from the hints, then
validate it. An unvalidated hint is not a proposal.

## Workflow

1. **Run the detector**, after the quote check above, and read its `FILE`/`SKIP` records as the
   corpus of record. Core tier always; expanded tier unless the operator passed `core`.
2. **Take candidates from `SECTION` records.** A candidate is one section with its emitted line
   range. Never a lone line pulled from a section; never a whole file when one section is the
   problem; never a boundary the detector did not report.
3. **Run the hard-deny gate first.** Anything matching a Gate 0 class leaves the candidate set and
   goes to the held-back section with its class and location. No destination, ever.
4. **Walk the ladder** for what survives. First match wins. Stop there.
5. **Derive and validate the glob** for every path-scoped proposal:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh" validate --glob '<derived>'
   ```

   A glob that comes back `zero-match`, `bad-bracket`, or `over-budget` **must not be proposed**.
   Re-derive, or drop the candidate to the subtree destination, or leave it where it is. Record the
   validation facts, match count and breadth, in the finding, because that is the evidence the
   operator gates on. An `over-broad` result is proposable but must be surfaced as such.
6. **Price each proposal**: what leaves the always-loaded budget, that the content is not inherited
   by a subagent and announces itself nowhere, and post-compaction behavior for that specific
   destination.
7. **Rank**, highest value first: always-loaded lines released × confidence, with promote-lane
   findings ranked on value alone since they carry no downside.
8. **Write the artifact**, then summarize inline. The artifact is the record; the summary is a view
   of it.

## Where the artifact goes

Write under the home `findings-artifact.md` "Where it lives" defines, which also owns the
constant slug, the branch axis, the self-ignore guard, and what the file contains.

If a prior artifact exists at that home, merge per the contract's re-run semantics rather than overwriting. An
operator's `declined` decision must survive a re-audit.

## The suppression surface

Before ranking, resolve the tracked suppression file `<home>/instruction-placement.yaml` across
its layers (`<home>` is the convention home that the marked pointer region in the root `AGENTS.md`
or `CLAUDE.md` binds, `docs/conventions` when no region binds one, not the memory-tier home the
artifact above is written under), old paths included while they exist, and print the old-path warning for each one found
([`${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`](../../reference/consumer-config.md)
"Layers and merge semantics"). Suppress every candidate whose `finding_id` it carries. That file is
how a decline reaches a checkout the findings artifact never does, so a sweep that ignores it
re-proposes decisions the operator already made elsewhere.

Derive a candidate's `anchor/v1` and `finding_id` by running `detect.sh identity`, never by hand.
`--file` is the repo-relative path:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh" identity --file <path> --start <n> \
  --lane demote|promote --destination <rung>
```

Three obligations, none optional. **Read, never write**: `realign` composes an entry behind its
per-item gate and nothing here does. **Report the suppressions**, each with its reason, date, and
contributing layer, and every entry that did *not* suppress: personal-only, malformed, or outside
this run's scope. **Exclude the surface, its layers and its old-path files**, because auditing the
file that records the decisions would make recording one perturb the next run. That exclusion is applied to the candidate
set after the detector has run, not to the corpus: the corpus document above stays the one owner of
what is swept, and the detector's coverage numbers keep counting every file it read.

## The content-home advisory

The two lanes judge sections. One question is about a whole file: whether a `CLAUDE.md` should be
the content home at all. For each `FILE` record of a tracked file named `CLAUDE.md` in a directory
migrate's plan covers (outside the trees `IP_EXCLUDED_TREES` in `${CLAUDE_PLUGIN_ROOT}/scripts/lib/discover.sh` names,
`.claude/` among them), whose content is anything other than the single line `@AGENTS.md`, report
one advisory. `.claude/CLAUDE.md` never gets one: `plan-migration.sh` emits no `DIR` row for it,
and a shim there would import `../AGENTS.md`.

> `<path>` holds project instructions that could live in `AGENTS.md`, where other coding agents
> read them too. Plan the move with `/instruction-placement:migrate plan`. Keep the `CLAUDE.md` as
> the one-line `@AGENTS.md` shim: migrate's `cutover-check` decides when shims can come out, and
> this audit never proposes removing one. Claude-specific text goes to `.claude/rules/<topic>.md`
> with a `paths:` glob, per migrate's routing.

It is not a finding: no `finding_id`, no status, nothing `realign` acts on. It cancels none of the
file's demote findings; the operator sequences those with the migration. Write it to the artifact's
advisory section. Whether the file should be split for progressive disclosure is
`docs-hygiene:audit-progressive-disclosure`, routed per [`context/routing-out.md`](context/routing-out.md).

## Routing out

A candidate can raise a question placement does not answer: whether the model still needs the
instruction, whether it is duplicated, whether the whole file should exist. Those belong to sibling
plugins, and each route is presence-gated with a documented fallback.

Read [`context/routing-out.md`](context/routing-out.md) when a candidate raises one, for the route
table and the two rules that keep routing from becoming silent dropping.

## Reporting honestly

- **Say what was not swept.** The detector's `SKIP` records and `SUMMARY` are the source. Report
  them rather than recounting by hand. A run that covered 200 of 2,000 files while reading like a
  full audit is the failure this rule exists to prevent.
- **Show the held-back list.** An operator who cannot see what the hard-deny gate excluded cannot
  tell a careful sweep from a shallow one.
- **Never report a saving without its cost.** Both belong in the same sentence.
- **Zero findings is a real result.** A repository whose instructions are already well-placed gets
  told so, not handed marginal proposals to justify the run.

## Hard rules

- **Read-only.** The only files this skill writes are its own findings artifact, untracked
  and never committed, and the docs cache `quote-check.sh` refreshes through `fetch-docs.sh`,
  outside the repository. A multi-repository run also adds the `instruction-placement/realign`
  worktree and branch per repository ("Over several repositories"). No edit to any instruction
  file, ever, not even an obviously correct one.
- **Never propose a glob that failed validation.** The check is mechanical and cheap; a guessed glob
  produces a rule that silently never fires, which is strictly worse than leaving the content alone.
- **Never propose demoting a hard-deny candidate**, under any argument, including an operator
  asking for it. Say what the class is and offer compression in place instead.
- **Never move content across the user/project boundary.** User-scope surfaces are read for
  duplicate detection only.
- **Never edit another tool's instruction files.** Cursor, Copilot, Windsurf, and Cline configs are
  read-only sources for the promote lane.
- **Deterministic output.** Files sort lexically, findings sort by rank then identifier, no
  timestamps outside frontmatter.

## Next

- The operator accepts placement findings: `/instruction-placement:realign`.
- A content-home advisory fired: `/instruction-placement:migrate plan`.

## Gotchas

Observed failure modes, each producing a finding that survives review by eye: the saving that is
not a saving, globs that look right and match nothing, safety rails that look path-local, and line
ranges that were read rather than measured. Read [`context/gotchas.md`](context/gotchas.md) before
finalizing a finding set.
