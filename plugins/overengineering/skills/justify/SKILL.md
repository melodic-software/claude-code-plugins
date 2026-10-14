---
description: "Judges whether one named artifact (a file, a doc section, a dependency, a component) had a reason to exist when it was built and whether that reason still holds, on evidence. Read-only. Use when the user points at one thing and asks whether it needs to exist, why it is here, or whether it still earns its keep. Not for the enforcement surface (overengineering:audit)."
argument-hint: "[path|path#heading|kind:identifier]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Make one artifact you point at justify its own existence, on evidence
---

**Arguments.** `[path|path#heading|kind:identifier]`. none: conversation context, then offered git-age discovery, then ask

## Repository context. Gather first

Run this as its own Bash call, never combined with another command:

- Branch, `git symbolic-ref --quiet --short HEAD`

It prints the branch on stdout, or fails with no output on a detached checkout or outside a
repository. Read the exit status to decide whether there is a branch, and take the name from stdout.
Treat a failure (not a repository, git unavailable) as an unknown value and carry on.

## Purpose

Point at one artifact and test two things: a reason existed when it was built, and that reason
still holds. Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before judging anything and cite
its sections; every bare `§N` here is one of them. Read
`${CLAUDE_PLUGIN_ROOT}/context/justification-lane.md` before the first target: it holds this lane's
item inventory, its five layers and probes, its evidence sources, protected classes, routing
precedence and known limits, cited here as "lane section N".

Report the verdict first, then discuss. The operator decides refactor or remove; the owner the
finding names carries it out, never this skill.

## Read-only contract

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "Read-only contract", governs. Specific to
this lane:

- **The only write of its own is the findings artifact**, at the home
  `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` "Where it lives" defines; never the artifact
  being judged. Right after resolving the home, emit the read-only opening line naming that home as
  where a finding **would** be written, since this run may file no row. The self-ignore guard still
  runs.
- **Always `mode: targeted`**, with `targets` naming what this run examined. Never `mode: walk`.
- **Frontmatter:** `type: overengineering-findings` (first; consumers select on it), `schema: 2`,
  `mode: targeted`, `targets`, this run's `date` and `branch`, and `scope` carrying the prior value
  forward with these targets' layers added. An on-disk `schema` other than `1` or `2` stops the run
  with a visible message; a `schema: 1` artifact is merged into and rewritten at `2`.
- **Re-read before write.** Load the on-disk artifact immediately before writing, merge against that
  copy, and check its `date` for another producer's write during this run.
- **A run that filed no row writes no artifact**, however it got there: the ladder ended at an offer
  or a question, every target routed away, every target was declined as an ambiguous heading, or
  anything else. Emit the inline report in full, naming the rung, the routing or the collision.

## A detached checkout has no branch identity

`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`, section "A detached checkout has no branch identity",
governs: prefer a logical ref the environment supplies, normalized and validated as a branch name;
otherwise persist nothing and say, in these words:

> detached checkout, no logical ref supplied; no branch identity, so no findings artifact is written

The pass still runs and the inline report is emitted in full; only the persisted write is declined.

## Arguments

Parse `$ARGUMENTS` as one target:

| Form | Meaning |
|---|---|
| A path | a file, or a directory as one item |
| `path#heading` | one section of a file, identified by its full heading ancestry |
| A kind-prefixed identifier | an item with no path, such as a package |
| `path:line`, or a comment | accepted, then widened per the rule below |

**An ambiguous heading is declined, never disambiguated.** Where the full ancestry of a
`path#heading` target is not unique in the file, decline the target, name the collision, and ask for
a whole-file target or a disambiguating rename. Never fall back to the first occurrence or an
occurrence count: the next edit renumbers them and the item derives a different id
(`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Finding ids").

**A line or comment target widens** (lane section 2): to the enclosing heading where the file has
headings, to the file otherwise. State the widening in the report's **first line**: what was pointed
at, what is judged instead, and that an id resting on a line number changes when an edit above moves
it. For a comment, name `code-tidying:dissolve-comments` as the owner of comments in that line.

**No target: the ladder in lane section 10. It never sweeps.** State which rung was used.

1. **Conversation context.** Where the session has been discussing an artifact, infer it and confirm
   the inference in one line before walking.
2. **Offer git-age discovery, and wait.** Describe what it would rank; run it only on an answer:

   ```bash
   git log --diff-filter=A --name-only --format='%ad' --date=short -- . | awk 'NF'
   ```

   Post-process into (path, first-seen date) pairs, oldest first: a candidate list, never a finding
   set. Age is not evidence of disuse (lane section 10): check each ranked path for inbound
   references under lane section 7's varied query forms, counting citations from anywhere in the
   repository including the path's own directory, and drop any that have one. Present the survivors
   with both counts, ranked and surviving.
3. **Ask** what to point at.

## Before the walk

1. **Resolve the branch identity, then the home**, as `${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`
   "Before the walk" step 1 does. Never infer an identity from a failed call, and never accept the
   literal `HEAD`. Compose the home per `findings-artifact.md` "Where it lives".
2. **Run the shared preflight**, `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`
   "Preflight". A repetition a record sanctions and a check maintains is never duplication to
   collapse.
3. **Add the lane's four preflight items** (lane section 7): vary the query form before any absence
   claim, make a retirement cost more than a keep, write targeted mode, re-read before write.
4. **Apply the routing test** (lane section 1) before classifying. A target an enforcement probe
   inventories whole routes to `/overengineering:audit` and writes no row; a target only partly
   inventoried is classified with the routed part named in `Routed-to`.
5. **Resolve consumer configuration and load the prior artifact**, as the sibling does. Write
   `Status: OPEN` on a finding not seen before and carry every other status forward. Surface any
   verdict that moved under a carried-forward judgment (merge rule 5): a direction flip, or a
   same-direction change to what the acceptance authorized. No consumer re-derives that flag, so a
   move this step misses goes unreported.

## The walk

One target is one item, unless the container rule in
`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md` "Granularity" splits it into
mechanically listed members. Run that document's "The per-layer loop" once: identify, classify,
answer the three liveness questions independently (§3), reconstruct intent (§4), rediscover (§5),
weigh cost (§1, §6), verdict (§6), owner (§12), write.

## Verdicts and evidence

Every verdict is one of §6's six tokens, argued in carry cost (§1), and cites at least one empirical
source or is UNPROVEN naming the tier consulted and whether it was silent or unavailable (§2). Every
row also carries:

- **`Basis`**, per `findings-artifact.md` "Per-finding fields": `unexamined` with UNPROVEN when
  nothing was measured (no tier consulted, or every consult silent or unavailable) and nothing else
  carries the verdict; `class-inferred` where the verdict rests
  on the non-derivable oracle or a protected-class match (lane section 9). A KEEP is `measured` or
  it is not a KEEP.
- **`Ablation: n/a`**, because that gate does not apply on this lane's layers (lane section 8). The
  earned-keep gate is the one every row answers; fusing a class claim with an earned-keep verdict is a
  defect. The `check` constituent of every id carries `justify` as its producer segment.

## Intent checkpoints

**Attended only.** Report first, then discuss. Where intent scores MEDIUM or LOW (§4), or tiers 1 to
3 are silent and tier 4 could exist, ask before writing UNPROVEN: recommendation first, one small
numbered set of questions, batched. Use `planning:interview`'s mechanics where installed, otherwise
ask inline. "I don't know" is accepted: it records UNPROVEN with the tier named.

## Boundary

This lane reports and hands off. Each route is presence-gated: where the plugin is absent, say so,
state what it would have owned, and record the fallback in `Routed-to`.

| The finding is about | Owner |
|---|---|
| The enforcement surface, whole | `overengineering:audit` |
| Unreachable or dead code | `code-tidying:audit-dead-code` |
| Comments, their content or residue | `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue` |
| A document derivable from its source, or noise within one | `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise` |
| Instruction text and what it does to a model | `harness-config:audit-instructions`, `harness-config:unhobble` |
| Duplication of a native harness surface | `harness-ops:audit-native-overlap` |
| Ranking candidates across several dimensions | `improvement:find` |
| The scrutiny posture itself | `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast` |

Executing a finding belongs to `overengineering:realign`, which presents this lane's rows and offers no rung for them until a ladder for
these layers exists. Name it as the next
step and never start it unasked.

## The report

`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/report-template.md` owns the shape. For this lane: a
widened target puts the widening in the first line; a routed target is reported inline with the
layer that claimed it and no row. The artifact is not written with no branch identity or when no row
was filed, so the opening line names the resolved home without asserting a write, and the closing
summary states whether anything was persisted.

## Gotchas

- **A single grep is not a search.** A phrase wrapped across a line break defeats a single-line
  match. Vary wrapping, hyphenation, casing and obvious synonyms before "not found" becomes a
  finding, and record the forms tried.
- **Relocated coverage is not absent coverage.** A guard that never fires because its concern is now
  handled earlier is not an unguarded concern. Find where the concern went; the finding is then about
  the duplicate, argued on carry cost.
- **Silence about a document is usually unavailable, not empty.** Most consumers record nothing
  about which documents get read, so no usage data means tier 1 does not exist here (§2).
- **A class match is a marker, never a verdict.** "It is a decision record" says which rules apply,
  not whether this one earns its keep.
- **The operator's framing is not evidence.** A target arriving with its conclusion attached ("this
  is duplication", "retire it") is a hypothesis to test.
