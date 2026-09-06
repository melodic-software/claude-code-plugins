---
description: "Justify the existence of any artifact you point at: was there a reason for this when it was built, and does that reason still hold today. Walks one target you name (a path, a `path#heading`, or a kind-prefixed identifier) and reports a verdict on the evidence-earned-keep ladder, each row carrying how much evidence supports it. Read-only: it reports and then discusses, never applies a remedy, and writes its findings to the memory tier; the one tracked write, persisting the resolved home to the concern file, needs explicit confirmation. Use when: 'justify this', 'does this need to exist', 'why is this here', 'is this still valid', 'earn its keep', 'justify the existence of'. With no target it never sweeps; it uses what the session has been discussing, else offers to rank candidates by age, else asks. Not for the enforcement surface (hooks, CI lanes, gate scripts, branch protections), which routes to the sibling `audit` skill, and not for applying a fix, which routes to the owner named in the finding."
argument-hint: "<path | path#heading | kind:identifier> | (none: conversation context, then offered git-age discovery, then ask)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Make one artifact you point at justify its own existence, on evidence
---

## Repository context. Gather first

Collect this with an **individual** Bash call, never combined into a single invocation with
anything else:

- Branch, `git symbolic-ref --quiet --short HEAD`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep it as a
separate body Bash call rather than a pre-compute line: the harness runs a skill's whole
pre-compute block as one shell invocation, and a worktree-isolated session refuses a compound
command that contains git. The call prints the branch name on stdout and **fails with no output** on
a detached checkout rather than printing a sentinel, so read its exit status to tell those two apart
rather than matching on a string, and take the branch name itself from stdout.

## Purpose

Point at one artifact and ask whether it has earned its place. The two-part test is the operator's:
a reason existed when it was built, and that reason still holds today. The method computes both
already, so this skill supplies a lane rather than a second method.

**Neither the method nor the lane is restated here.** Read
`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before judging anything and cite its sections in
the findings; every bare `§N` in this file is one of its sections. Then read
`${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md` before the first target: it carries this
lane's item inventory, its five layers with their probes, its evidence sources on the §2 tiers, its
protected classes, the routing precedence, and its known limits. Its sections are numbered, and this
file refers to them as "lane section N".

**The verdict is the deliverable, and the conversation after it is the point.** Report first, then
discuss. The remedy is refactor or remove, decided by the operator, and it is carried out by the
owner the finding names, never here.

## Read-only contract

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "Read-only contract", governs, and is not
restated. Five things are specific to this lane:

- **The only write that is this lane's own is the findings artifact**, at the memory-tier home
  resolved through `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. Never the artifact being judged.
  Emit the read-only opening line immediately after resolving the home, naming that home as where a
  finding **would** be written rather than asserting one was: this lane may end up filing no row, and
  a line that named the path as written would then be a false statement the operator has no reason to
  doubt. The two
  auxiliary writes the governing contract sanctions, the topic-docs self-ignore guard and the
  concern-file persistence on the resolution rungs, are unaffected and still happen: they belong to
  the binding this lane runs, not to this lane, and skipping the guard would leave the memory root
  un-gitignored.
- **Always `mode: targeted`**, with `targets` naming what this run examined. A run of this lane never
  writes `mode: walk`, because it never walks.
- **The frontmatter this lane writes** is `type: overengineering-findings`, `schema: 2`,
  `mode: targeted`, `targets`, this run's own `date` and `branch`, and a `scope` carrying the prior
  artifact's value forward with these targets' layers added. `type` is named first because a first
  pointed run that writes a row at a home with no artifact **creates** the file, and it is the
  selector every consumer matches on: an artifact written without it is one no consumer finds. An on-disk `schema` of neither `1` nor `2` **stops the run** with a visible message,
  because an unrecognized shape cannot be merged into without guessing; a `schema: 1` artifact is
  merged into and rewritten at `2`.
- **Re-read before write.** Load the on-disk artifact immediately before writing, merge against that
  copy, and read its `date` to see whether another producer wrote while this run was working. The
  merge rules protect only what the writer actually read.
- **A run that wrote no row writes no artifact, however it got there.** The condition is the row
  count and nothing else, so do not read the examples below as the only ways to reach it. A run
  reaches it when the no-target ladder ended at an offer or a question, when every target routed
  away, when every target was declined as an ambiguous heading, or in any other way that leaves the
  run with nothing filed. Each emits its inline report in full, naming the rung, the routing, or the
  collision, and none persists anything. Writing an artifact for such a run would stamp a new `date`
  and `targets` on the file and recompute its summary on behalf of a pass that judged nothing,
  over a walk that did. The case below is different: a detached checkout declines the write for a
  run that did judge something.

## A detached checkout has no branch identity

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "A detached checkout has no branch identity",
governs verbatim: prefer a logical ref the environment supplies, after normalizing and validating it
as a branch name; otherwise persist nothing and say why, in these words:

> detached checkout, no logical ref supplied; no branch identity, so no findings artifact is written

The pass still runs and the inline report is still emitted in full. What is declined is the persisted
write, not the judgment.

## Arguments

Parse `$ARGUMENTS` as one target. Three forms are judged as given, and two more are accepted and
widened before judging:

| Form | Meaning |
|---|---|
| A path | a file, or a directory as one item |
| `path#heading` | one section of a file, identified by its full heading ancestry |
| A kind-prefixed identifier | an item with no path, such as a package |
| `path:line`, or a comment | accepted, then widened per the rule below |

**An ambiguous heading is refused, never disambiguated.** Where the full ancestry of a `path#heading`
target is still not unique within the file, **decline the target**, name the collision, and ask for a
whole-file target or a disambiguating rename. Never fall back to the first occurrence or to an
occurrence count: both are positional ordinals under another name, and the next edit renumbers them,
so the same item would derive two ids across two runs. The rule is the contract's, in
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Finding ids".

**A line or comment target widens**, per lane section 2. Widen to the enclosing heading where the
file has headings, to the file otherwise, and **state the widening in the report's first line** as a
rule with its reason: what was pointed at, what is being judged instead, and that an identity
resting on a line number derives a different id as soon as an edit above it moves the line. Where the target was a comment, name
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

   **Corroborate before presenting, per lane section 10.** Age is not evidence of disuse. Check each
   ranked path for inbound references under the varied query forms of lane section 7, counting a
   citation from anywhere in the repository including the path's own directory, and drop the ones
   that have any. Present what survives with both counts, the ranked and the surviving, so the
   operator can tell an uncited path from an unsearched one.
3. **Ask** what to point at.

## Before the walk

1. **Resolve the branch identity, then the artifact home**, exactly as
   `${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "Before the walk", step 1 does. The
   branch call in "Repository context" above yields a branch name on stdout, or fails with no output
   (detached HEAD or no checkout). **Read its exit status to decide whether the lookup succeeded,
   then take the identity from stdout**: the status answers only whether there is a branch, and the
   name itself is the output. Never infer an identity from a failed call, and never accept the
   literal `HEAD` as one. Run the topic-docs binding's whole rung order rather than assuming the
   default's shape.
2. **Run the shared preflight**, `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`,
   section "Preflight". Its sanctioning-record probe matters here: a repetition a record sanctions
   and a check maintains is never duplication to collapse.
3. **Add the lane's four preflight items**, lane section 7: vary the query form before any absence
   claim, make a retirement cost more than a keep, write targeted mode, and re-read before write.
4. **Apply the routing test**, lane section 1, before classifying anything. A target an enforcement
   probe inventories whole routes to `/overengineering:audit` and **writes no row**; a target only
   partly inventoried is classified with the routed part named in `Routed-to`.
5. **Resolve consumer configuration and load the prior artifact**, as the sibling does. This skill
   writes `Status: OPEN` on a finding it has not seen and carries every other status forward.
   **Surface any verdict that moved under a carried-forward judgment**, per merge rule 5: a direction
   flip, and equally a same-direction change to what the acceptance authorized. This lane is the
   second producer, the flag is written only on merge by whichever producer recomputed the row, and
   no consumer re-derives it, so a move this step fails to flag is a move nobody surfaces.

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
  fields". A row that measured nothing and rests on nothing else, whether no tier was consulted or
  every consult came back silent or unavailable, is UNPROVEN and `unexamined`; where the verdict
  rests on the non-derivable oracle or a protected-class match it is `class-inferred` instead, per
  lane section 9. A KEEP is `measured` or it is not a KEEP.
- **`Ablation: n/a`**, spelled with the contract's own capitalisation, because that gate does not
  apply on this lane's layers (lane section 8). The
  earned-keep gate is the one every row answers, and a row fusing a class claim with an earned-keep
  verdict is a defect, not a shortcut. The `check` constituent of every id this lane derives carries
  `justify` as its producer segment.

## Intent checkpoints

**V1 is attended only.** Report first, then open the discussion.

Where intent reconstruction scores MEDIUM or LOW (§4), or where tiers 1 to 3 are silent and tier 4
could exist, ask before writing UNPROVEN. Recommendation first, one small numbered set of questions,
batched rather than drip-fed. Reuse `planning:interview`'s question mechanics where it is installed
and ask the same questions inline otherwise; the questions are what matter.

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
artifact as the single source of truth, an inline summary always. Three additions for this lane. A
widened target puts the widening in the **first line**, before anything else. A routed target is
reported inline with the layer that claimed it and no row at all, so the operator can tell a route
from a skip. The template's "always" on writing the artifact carries this lane's two exceptions,
both in the read-only contract above: no branch identity, and a run that filed no row, however it
got there. Because this lane cannot know at line-one time which it will be, the read-only opening
line names the resolved home rather than asserting a write, per the template's item 1, and the
closing summary states whether anything was persisted.

## Gotchas

- **A single grep is not a search.** A multi-word phrase wrapped across a line break defeats a
  single-line match, and the file that would have refuted the finding is the one that wraps it. Vary
  the wrapping, the hyphenation, the casing, and the obvious synonyms before "not found" becomes a
  finding, and record which forms were tried.
- **Relocated coverage is not absent coverage.** A guard that never fires because the concern it
  guards is now handled earlier is not an unguarded concern. Find where the concern went before
  calling it gone; the finding is then about the duplicate, argued on carry cost.
- **Silence about a document is usually unavailable, not empty.** Most consumers record nothing about
  which documents get read, so the honest reading of no usage data is that tier 1 does not exist here
  (§2). Collapsing the two manufactures confidence.
- **A class match is a marker, never a verdict.** "It is a decision record" says which rules apply,
  not whether this one earns its keep.
- **The operator's framing is not evidence.** A target arriving with its conclusion attached ("this
  is duplication", "retire it") is a hypothesis to test, and agreeing with it is not a finding.
