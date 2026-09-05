---
description: "Justify the existence of any artifact you point at, against the two-part test: was there a reason for this when it was built, and does that reason still hold today. Walks one target you name (a path, a `path#heading`, or a kind-prefixed identifier such as a package) and reports a verdict per the plugin's evidence-earned-keep ladder, with every row carrying how much evidence actually supports it. Read-only: it reports and then discusses, and never applies a remedy. Use when: 'justify this', 'does this need to exist', 'why is this here', 'is this still valid', 'earn its keep', 'justify the existence of'. With no target it never sweeps the repository; it uses what the session has been discussing, else offers to rank candidates by age, else asks. Not for the enforcement surface (hooks, CI lanes, gate scripts, branch protections), which routes to the sibling `audit` skill, and not for applying a fix, which routes to the owner named in the finding."
argument-hint: "<path | path#heading | kind:identifier> | (none: conversation context, then offered git-age discovery, then ask)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Make one artifact you point at justify its own existence, on evidence
---

## Pre-computed context

- Branch: !`git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "no branch ref (detached HEAD or no checkout)"`

## Purpose

Point at one artifact and ask whether it has earned its place. The two-part test is the operator's:
a reason existed when it was built, and that reason still holds today. The method computes both
already, so this skill supplies a lane rather than a second method.

**The method is not restated here.** Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before
judging anything, and cite its sections in the findings. Every bare `§N` in this file is a section of
that document.

**The lane is not restated here either.** `${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md`
carries this lane's item inventory, its five layers with their probes, its evidence sources on the §2
tiers, its protected classes, the routing precedence, and its known limits. Read it before the first
target. Its own sections are numbered, and this file refers to them as "lane section N".

**The verdict is the deliverable, and the conversation after it is the point.** Report first, then
discuss. The remedy is refactor or remove, decided by the operator, and it is carried out by the
owner the finding names, never here.

## Read-only contract

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "Read-only contract", governs, and is not
restated. Three things are specific to this lane:

- **The one write is the findings artifact**, at the memory-tier home resolved through
  `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. Never the artifact being judged. Emit the
  read-only opening line naming the resolved path, immediately after resolving it.
- **Always `mode: targeted`**, with `targets` naming what this run examined. A run of this lane never
  writes `mode: walk`, because it never walks.
- **Re-read before write.** Load the on-disk artifact immediately before writing, merge against that
  copy, and record its `date`. Another session may have written since this run started, and the merge
  rules protect only what the writer actually read.

## A detached checkout has no branch identity

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "A detached checkout has no branch identity",
governs verbatim: prefer a logical ref the environment supplies, after normalizing and validating it
as a branch name; otherwise persist nothing and say why, in these words:

> detached checkout, no logical ref supplied; no branch identity, so no findings artifact is written

The pass still runs and the inline report is still emitted in full. What is declined is the persisted
write, not the judgment.

## Arguments

Parse `$ARGUMENTS` as one target in one of three forms:

| Form | Meaning |
|---|---|
| A path | a file, or a directory as one item |
| `path#heading` | one section of a file |
| A kind-prefixed identifier | an item with no path, such as a package |

**A line or comment target widens**, per lane section 2. Widen to the enclosing heading where the
file has headings, to the file otherwise, and **state the widening in the report's first line**,
naming both what was pointed at and what is being judged. Where the target was a comment, name
`code-tidying:dissolve-comments` as the owner of comments in that same line.

**No target: the ladder in lane section 10, and it never sweeps.** State which rung was used.

1. **Conversation context.** Where the session has been discussing an artifact, infer it and confirm
   the inference in one line before walking.
2. **Offer git-age discovery, and wait.** Describe what it would rank, run it only on an answer:

   ```bash
   git log --diff-filter=A --name-only --format='%ad' --date=short -- . | awk 'NF'
   ```

   Post-process into (path, first-seen date) pairs, oldest first. The output is a candidate list to
   choose from, never a finding set.
3. **Ask** what to point at.

## Before the walk

1. **Resolve the branch identity, then the artifact home**, exactly as
   `${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "Before the walk", step 1 does. The
   precompute above is a convenience, not the source of truth; where its line is absent, run
   `git symbolic-ref --quiet --short HEAD` and read the exit status. Run the whole rung order in the
   topic-docs binding rather than assuming the default's shape.
2. **Run the shared preflight**, `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`,
   section "Preflight". Its sanctioning-record probe is lane-independent and matters here: a
   repetition a record sanctions and a check maintains is never duplication to collapse.
3. **Add the lane's four preflight items**, lane section 7: vary the query form before any absence
   claim, make a retirement cost more than a keep, write targeted mode, and re-read before write.
4. **Apply the routing test**, lane section 1, before classifying anything. A target an enforcement
   probe inventories whole routes to `/overengineering:audit` and **writes no row**; a target only
   partly inventoried is classified with the routed part named in `Routed-to`.
5. **Resolve consumer configuration and load the prior artifact**, as the sibling does. This skill
   writes `Status: OPEN` on a finding it has not seen and carries every other status forward.

## The walk

One target is one item, unless the container rule in
`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`, section "Granularity", splits it into
mechanically-listed members. The per-item loop is that same document's, section "The per-layer loop",
applied once rather than per layer: identify, classify, answer the three liveness questions
independently (§3), reconstruct intent (§4), rediscover (§5), weigh cost (§1 and §6), verdict (§6),
owner (§12), write.

## Verdicts and evidence

Every verdict is one of the six tokens in §6, argued in carry cost (§1), and cites at least one
empirical source or is UNPROVEN naming the tier consulted and whether it was silent or unavailable
(§2). Beyond that, every row this lane writes carries:

- **`Basis`**, per `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Per-finding
  fields". A row with no tier consulted is UNPROVEN and `unexamined`. A KEEP is `measured` or it is
  not a KEEP.
- **`ablation: n/a`**, because the ablation gate does not apply on this lane's layers (lane section
  8). The earned-keep gate is the one every row answers, and a row that fuses a class claim with an
  earned-keep verdict is a defect, not a shortcut.

The `check` constituent of every id this lane derives carries `justify` as its producer segment.

## Intent checkpoints

**V1 is attended only.** Report first, then open the discussion.

Where intent reconstruction scores MEDIUM or LOW (§4), or where tiers 1 to 3 are silent and tier 4
could exist, ask before writing UNPROVEN. Recommendation first, one small numbered set of questions,
batched rather than drip-fed. Where `planning:interview` is installed, reuse its question mechanics;
otherwise ask the same questions inline as a numbered list. The questions are what matter, so nothing
is lost but the mechanics.

**"I don't know" is an accepted answer.** It records UNPROVEN with the tier named, and resolves the
item in neither direction.

## Boundary

This lane reports and hands off. Each route is presence-gated: where the plugin is absent, say so
inline, state what it would have owned, and record the fallback in `Routed-to`.

| The finding is about | Owner |
|---|---|
| The enforcement surface, whole | `overengineering:audit` |
| Unreachable or dead code | `code-tidying:audit-dead-code` |
| Comments, their content or residue | `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue` |
| A document derivable from its source, or noise within one | `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise` |
| Instruction text and what it does to a model | `claude-config:audit-instructions`, `claude-config:unhobble` |
| Duplication of a native harness surface | `claude-ops:audit-native-overlap` |
| Ranking candidates across several dimensions | `improvement:find` |
| The scrutiny posture itself | `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast` |

Executing a finding belongs to `overengineering:realign`, which **presents** this lane's rows and
offers no rung for them until a ladder for these layers exists. Name it as the next step and never
start it unasked.

## The report

`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/report-template.md` owns the output shape: the findings
artifact as the single source of truth, an inline summary always. Two additions for this lane. A
widened target puts the widening in the **first line**, before anything else. A routed target is
reported inline with the layer that claimed it and no row at all, so the operator can tell a route
from a skip.

## Gotchas

- **A single grep is not a search.** A multi-word phrase wrapped across a line break defeats a
  single-line match, and the file that would have refuted the finding is the one that wraps it. Vary
  the wrapping, the hyphenation, the casing, and the obvious synonyms before "not found" becomes a
  finding, and record which forms were tried.
- **Relocated coverage is not absent coverage.** A guard that never fires because the concern it
  guards is now handled earlier is not an unguarded concern. Find where the concern went before
  calling it gone; the finding is then about the duplicate, argued on carry cost, not about a hazard
  nobody covers.
- **Silence about a document is usually unavailable, not empty.** Most consumers record nothing about
  which documents get read, so the honest reading of no usage data is that tier 1 does not exist here
  (§2). Collapsing the two is how a report manufactures confidence.
- **A class match is a marker, never a verdict.** "It is a decision record" says which rules apply,
  not whether this one earns its keep.
- **The operator's framing is not evidence.** A target arriving with its conclusion attached ("this
  is duplication", "retire it") is a hypothesis to test, and agreeing with it is not a finding.
