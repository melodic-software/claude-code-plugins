---
description: "Read-only sweep for instruction content on the wrong surface. Conventions in an always-loaded CLAUDE.md/AGENTS.md really scoped to one file type or subtree (demote), and normative conventions stranded in ordinary docs Claude never loads (promote). Proposes a destination per candidate: a path-scoped `.claude/rules/` file whose `paths:` glob is machine-checked first, a nested AGENTS.md plus its CLAUDE.md shim, a skill, a linter, or deletion. Safety rails covering irreversible actions, secrets, data, publication, compliance, and agent authority are hard-denied from demotion and held back. Every proposal is priced: deferred content is invisible to subagents and absent after compaction until re-triggered. Use when: 'my CLAUDE.md is too long', 'convert this to rules', 'what should be a path-scoped rule', 'move conventions to .claude/rules', 'find conventions in our docs', 'nested CLAUDE.md candidates', 'audit instruction placement'. Emits a findings artifact; the sibling realign skill applies what you accept."
argument-hint: "[core|expanded] [path ...]. Default: core+expanded over the whole repository"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh:*)",
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

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" audit 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

Instruction content has a load cost set by the surface it sits on, and most repositories put
everything on the most expensive one. A convention that only matters when someone edits a `.cs` file
is paid for in every session, in every conversation, whether or not any C# is touched.

**The saving is context, not obedience.** Official guidance warns that bloated instruction files
cause Claude to ignore the instructions inside them, but this plugin measured that specific claim
and did not reproduce it: 32 trials at two bloat levels, up to 1,927 lines, found 100% compliance
whether the convention was always-loaded or path-scoped
([`../../evals/adherence-results.md`](../../evals/adherence-results.md)). So propose moves on
context cost and on reaching content Claude never loads, never by promising the operator their
instructions will be followed better afterwards.

This skill finds content whose scope is narrower than the surface carrying it, and content whose
surface Claude never reads at all, and proposes where each should go.

**It is read-only.** Every finding is a proposal; the operator decides, and `realign` executes.

## Read these before adjudicating anything

The judgment lives in the plugin's context files, not in this hub. Do not re-derive them.

| Read | For |
|---|---|
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | The hard-deny gate, the decision ladder, glob derivation, the promote lane |
| [`../../context/corpus.md`](../../context/corpus.md) | What is swept, in what order, and what is never touched |
| [`../../context/verified-mechanics.md`](../../context/verified-mechanics.md) | When each surface loads, and the three gaps that constrain every proposal |
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | The artifact's shape, location, and re-run merge semantics |

A proposal that contradicts `verified-mechanics.md` is wrong even if it looks like a saving. The
common one: moving a section into `.claude/rules/` *without* a `paths:` glob, which costs exactly
what it cost before.

## The two lanes

**Demote**. Content already in the instruction layer, sitting higher than its scope warrants. The
saving is real but so is the trade: what defers is invisible to subagents and absent after
compaction until re-triggered. Price it, every time.

**Promote**. Normative content in ordinary documentation that Claude loads *never*. There is no
presence to lose, so the gaps do not apply and any working destination is a strict improvement. The
live risk here is duplication, not context: resolve single-source-of-truth per candidate using the
rubric's table rather than reflexively copying.

## Facts before judgment

Run the detector first and build every finding on what it emits:

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
does not know whether `.ts` is the candidate's real scope. Derive the glob from the hints, then
validate it. An unvalidated hint is not a proposal.

## Workflow

1. **Run the detector** and read its `FILE`/`SKIP` records as the corpus of record. Core tier
   always; expanded tier unless the operator passed `core`.
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
6. **Price each proposal**: what leaves the always-loaded budget, subagent invisibility, and
   post-compaction behavior for that specific destination.
7. **Rank**, highest value first: always-loaded lines released × confidence, with promote-lane
   findings ranked on value alone since they carry no downside.
8. **Write the artifact**, then summarize inline. The artifact is the record; the summary is a view
   of it.

## Where the artifact goes

Resolve the project key and write under it. `findings-artifact.md` owns the full path shape:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

The plugin data directory is keyed to the plugin identifier and nothing else, so an unkeyed filename
is one file per **machine**: a later run in a different repository would read this one's findings as
its own. Never skip the key. If a prior artifact exists for this key, merge per the contract's
re-run semantics rather than overwriting. An operator's `declined` decision must survive a re-audit.

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

- **Read-only.** The only file this skill writes is its own findings artifact, outside the
  repository. No edit to any instruction file, ever, not even an obviously correct one.
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

## Gotchas

Ten observed failure modes, each producing a finding that survives review by eye: the saving that is
not a saving, globs that look right and match nothing, safety rails that look path-local, and line
ranges that were read rather than measured. Read [`context/gotchas.md`](context/gotchas.md) before
finalizing a finding set.
