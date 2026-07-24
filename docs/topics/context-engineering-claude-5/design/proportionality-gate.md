---
outcome: gate-closed-escalated
tier: A
date: 2026-07-24
---

# Phase 2.5 — proportionality gate on D1–D7

The record PLAN.md's Phase 2.5 sanity checks assert against. It carries every detector's
disposition with its reason, the escalation verdict, the operator's decision on that escalation, the
`OPINION`-tier policy, the D1 scope answers the corroboration document parked here, and the homing
map Phase 5 would otherwise have produced separately.

**Sequencing note.** This gate ran *before* Phase 2, inverting PLAN.md's stated order. The reason is
in [design-resolution.md](design-resolution.md) lines 103–106: the Tier A classification, and with it
Phase 2's existence, "rests on 'new checks across four plugins' and 'a versioned criteria catalog
consumed by more than one plugin'", and "if the proportionality gate leaves one detector and a set of
calibration inputs, neither signal fires as stated." Information flows one way — this gate's verdict
narrows Phase 2, while Phase 2's shape narrows nothing here. Deciding the seam first would have
decided it against a premise this gate deletes. Operator approved the swap.

## The test

Applied uniformly to all seven, and stated before any disposition was assigned:

> What does this detect that its named incumbent does not, such that a written false-positive story
> is possible for it?

Two corollaries the plan already fixed. Useful authoring guidance is not a detection. Restating a
page of official documentation is not a detection.

Dispositions come from one of three values: `detector`, `calibration input to <named incumbent>`, or
`deferred with trigger`.

**Two tests, not one — stated because the first draft conflated them.** The test above asks whether
an *incumbent already covers it*. A separate question asks whether the rule is *officially backed*.
They are orthogonal, and a rule can fail either independently: S3 is fully confirmed by official
docs **and** the largest gap; the S6 interface half is unowned by any incumbent **and** unconfirmed
by any page. Demoting a rule for being `OPINION`-tier is legitimate, but it is not the coverage
test and must not be reported as though it were. Every row below names which test it fails.

**The vocabulary needed a fourth value.** D4 emits nothing — it withholds — so neither `detector`
nor `calibration input` describes it, and forcing it into the three-value box would have hidden what
it is. `suppression input` is added rather than stretched, and the up-front claim that three values
were fixed before any disposition was assigned is corrected here rather than left standing.

## Dispositions

Each row carries two independent answers, because conflating them is what the first draft got wrong.
**Lands as** answers the coverage test — what new or changed surface does this produce.
**Enablement** answers the evidence test — is it officially backed and therefore on by default, or
`OPINION`-tier and therefore opt-in.

| D | § | Lands as | Enablement | Reason and evidence |
|---|---|---|---|---|
| D1 | S3 | **new check I12** in `audit-instructions` | on — `ANTHROPIC-DOCS` | No incumbent compares two instruction surfaces against each other; `extract-ssot` finds repetition, not contradiction. `coverage-matrix.md:26` (`GAP`, "the largest one"); `official-corroboration.md:38` — memory doc "Consistency", plus "**No tool performs this review**" |
| D2 | S6 | extends **I9's Remediate line** in `audit-instructions` | off — `OPINION` | Fails the *evidence* test, not the coverage test — the first draft reported it the other way round. I9 already detects the same artifact (an example block pinning the model's approach); R-A adds only where the information should go instead. `skill-quality:check` cannot host it: its contract is "NO model invocation… reproducible in CI", and representational-equivalence judgement is not reproducible. `official-corroboration.md:41`; `check-skill.sh:3-4` |
| D3 | S8 | **new check** in `audit-instructions`, beside I3 | off — `OPINION` (pending S8 re-verification) | Not `extract-ssot`: that refuses below three instances and picks a home by content type, never by proximity to what is governed. Not I3 either — **different axis**: I3 is load *timing*, D3 is definition-site *locality*, and an instruction can be correctly deferred and still misplaced. `extract-ssot/SKILL.md:15,84`; `criteria.md:66-74` |
| D4 | S13 | extends **I6 and I8** with a stopping condition, `claude-config`-local | **on** — suppressor inversion | Neither I6 nor I8 carries any a-priori bound: I6's escape is a rewrite concession, I8's remediation is unconditional. And no trimming rule outside `claude-config` needs to consult it — every `docs-hygiene` trimmer already owns a local stopping condition. One consumer, so a local check, not a shared artifact. `criteria.md:97-105, 117-126` |
| D5 | S10+S14 | **nothing built** | deferred | The one remainder with no incumbent to calibrate. **Trigger:** an official page names artifacts or a reference ranking as normative, or a reproducible defect shape makes it auditable. `coverage-matrix.md:47-49`; `official-corroboration.md:46, 50, 268-269` |
| D6 | S7 remainder | **splits by the surface partition** — tightens I3's Remediate for non-memory surfaces; folds into the C3 revision for memory surfaces | on — `ANTHROPIC-DOCS` | I3 names the right destinations but supplies no qualifying test and no cost: nothing in it says `@path` fails to defer, so an auditor could satisfy its letter and change the load profile not at all. And I3 is contractually barred from memory surfaces, which is where the rule matters most. `criteria.md:25-30, 66-74`; `official-corroboration.md:68, 104-107` |
| D7 | S4 remainder | folded into **one consolidated C3 revision** in `claude-memory:audit` | on — `ANTHROPIC-DOCS` | Its premise is official policy on an existing page, so it is not a gap — but C3 *already is* the routing table and is missing two rows the plugin's own reference material supplies: auto-memory as a destination, and `@path` as a non-deferring one. **D7 and D6's memory half are the same rule**; filing them separately would emit two findings on one misplaced section. `official-corroboration.md:188-196`; `claude-memory` `criteria.md:56-72` |

**One new officially-backed check survives** (D1). One further new check ships `OPINION`-tier and
default-off (D3). Everything else is an edit to a check that already exists. Nothing lands in
`docs-hygiene` or `skill-quality` at all.

## Escalation

PLAN.md: "If only D1 survives as a detector, stop and re-derive the deliverable's shape before Phase
3 builds a catalog... That re-derivation is a user-approval gate, not an implementation detail."

The condition fired. **The operator approved re-deriving the shape** on 2026-07-24, rather than
continuing with the full machinery or promoting a demoted detector back. The re-derived shape is
recorded in PLAN.md's rewritten phases; its summary is below.

### Re-derived shape

The machinery and the payload were premised on different things, and only one premise died.

- **The catalog as a new cross-plugin contract is dropped.** It was justified by "a versioned
  criteria catalog consumed by more than one plugin". With one detector, D1's criteria extend the
  live `criteria.md` inside `audit-instructions` — the plugin that already owns the surface
  inventory D1 compares across — as check I12. That is an in-place minor version bump of an existing
  catalog, not a new contract surface, not a relocation, and not a materialization cluster.
- **The convention-registry owner doc and its row go with it.** The registry gates a *new
  cross-plugin convention*. Extending one plugin's own reference file is not one.
- **The sweep survives, and its justification never depended on detector count.** The Brief's value
  claim is that every incumbent gets applied, in order, repeatedly, against a named target. Its
  payload is `/doctor`, `audit-instructions`, `claude-memory`, `docs-hygiene`, `skill-quality`, and
  `plugin-quality` — plus D1. Removing six detectors removes six of its steps' *authors*, not its
  reason to exist.
- **Cross-plugin dispatch needs no shared criteria.** `docs/PLUGIN-PHILOSOPHY.md` "Design boundary"
  sanctions "an optional namespaced skill invocation" as a public seam. The sweep invokes each
  incumbent; each incumbent reads its own criteria. Nothing crosses a plugin boundary except an
  invocation.

#### Is the sweep a component or a runbook a human could run by hand?

The cross-vendor review put this sharply: once the checks live inside the incumbents, an operator
could invoke each incumbent directly and get the same checking behavior, so what is the sweep's own
cohesive capability? The first draft asserted one instead of arguing it. Arguing it.

**The checks are delegated. The run semantics are not, and they are the product.** Invoking the
incumbents by hand yields none of the following, and none of them belong to any incumbent:

- **The derived exclusion set** — registered byte-identical cluster copies, vendored upstream
  materializations, and worktrees. A hand-run pass that trims one of the 13 `hook-utils.sh` copies
  breaks a sync path and reds CI. No incumbent knows this repository's exclusion classes.
- **The three-scope inventory** — managed policy, user, and project, inventoried *before* any fix
  applies. D1 cannot see a repo-versus-user conflict from a repo-only run, and the managed tier must
  be read without ever being remediated. Each incumbent sees only what it is pointed at.
- **Finding identity and a machine-readable report** — the property that makes two runs diffable
  rather than compared by reading. Prose findings from six separately-invoked skills are not a set.
- **Idempotence, suppression memory, and resumability** — a deliberately-kept finding must not
  resurface; a run interrupted at skill 140 of 181 must resume rather than restart. That state is
  per-target and per-run, which is precisely what no individual check holds.
- **One human gate per run instead of one per finding**, with mutation behind an explicit override.

So the capability is *a repeatable, diffable, resumable, exclusion-aware pass over a target's
instruction surface*. The checks are its content; the run contract is its substance. That is also
why the re-run contract survived the gate while the catalog did not — it was always the sweep's own
work, never the catalog's.

One structural note that lowers the bar this has to clear: the sweep is a **skill inside
`claude-config`**, not a new plugin. `PLUGIN-PHILOSOPHY.md`'s "one cohesive capability" and
"independently useful vertical slice" tests apply to the plugin, and `claude-config` already passes
them — it owns the Claude Code configuration plane and already builds the surface inventory the
sweep consumes.

#### The rest of the re-derived shape

- **The re-run contract survives, scoped down.** Idempotence is still the headline acceptance
  criterion and still needs a machine-comparable definition, but it is now defined over the sweep's
  own mechanical-tier output rather than over a multi-detector program.
- **Phase 5's homing map is discharged here** — see below. It would have been a seven-row table
  restating this one.

**What remains of Phase 2.** At most one artifact still crosses plugin boundaries: D4's carve-out,
consulted by whichever trimming rules turn out to need it. Phase 2 is therefore reduced to a single
question — whether that carve-out is duplicated per plugin, registered behind a sync script, or
needs no seam at all because every rule consulting it lives in one plugin — and it is answered in
[seam-resolution.md](seam-resolution.md).

### Ground-truth verification independently strengthened this

Two read-only verification passes checked `design-resolution.md`'s factual basis against the live
repository at `cbf27e88a9`. Three of its load-bearing claims are refuted, and every refutation cuts
the same direction — *against* relocating or sharing the catalog.

- **The drift checker is structurally blind to a criteria catalog.** `design-resolution.md:60-65`
  and PLAN.md both claim a byte-identical catalog copy landing in a second plugin trips
  `check-cross-plugin-source-drift.sh` as an unregistered cluster, and that registering the cluster
  is the sanctioned resolution. False. The script clusters on the **full path-within-plugin**
  (`check-cross-plugin-source-drift.sh:58`), and a criteria catalog lives at
  `skills/<skill-name>/reference/criteria.md` where the skill name differs by construction —
  `audit-instructions`, `audit-permission-grants`, `audit`, `quality-gate`. Four such files exist
  today at four distinct paths and form **zero clusters**; `--check` exits 0. The skip-list argument
  was necessary but not sufficient. So the CI safety net cited as shape 4's guarantee never fires
  for this artifact, and drift would be invisible rather than caught.
- **Relocating the catalog breaks a green CI gate.** All three parse paths are bare skill-relative
  markdown links in `audit-instructions/SKILL.md`; `plugins/skill-quality/scripts/check-skill.sh`
  existence-checks every skill-internal ref, and moving the file produces `broken skill-internal
  ref: reference/criteria.md`. Worse for the relocated shape: after the move, the natural
  `](../../reference/criteria.md)` form escapes that extractor entirely, so CI goes green whether or
  not the ref resolves. The gate that catches the move is the same gate that stops watching once the
  move is made.
- **The catalog has no frontmatter at all.** `Version: 1.0.0` is body prose on line 3 under an H1.
  The `sync-standards-contract.sh` bump machinery reads a YAML frontmatter key, so adopting that
  shape starts with adding frontmatter to a live contract surface — a step no document costed.

Two further corrections to the same document, neither changing the verdict: the
canonical-source-materialized-per-plugin pattern runs **five** times, not three
(`sync-parse-concern-value.sh` and `sync-resolve-convention-pattern.sh` were missed, and they are
precisely the explicit-list shape a catalog would need), and `reference/artifact-protocol.md` is a
*destination*, not a canonical source — the source is `docs/PLUGIN-ARTIFACT-PROTOCOL.md`.

**And the adoption cost is six to seven registration points, not one:** the per-plugin copies, a
dedicated sync script, a `lib/<name>.test.sh`, a new CI job in the three-step
`--check` / test / `--check-bump` shape *with* `fetch-depth: 0`, that job's name added to the
`ci-status` aggregate or the gate never blocks, a registry entry that is unreachable here because no
cluster can form, and a Convention registry row. Two operational costs go with it: byte-identity
forbids relative markdown links in the canonical source, and every content edit becomes a
fleet-wide version event — a manifest bump in *every* carrying plugin plus a changelog entry whose
heading matches the new version string, or CI reds.

The proportionality verdict and the ground-truth verdict were reached independently and agree:
**the catalog stays where it is, and D1 extends it in place.**

### Reconciling with the Brief's one-anchored-source criterion

PLAN.md's "Re-runnable by design" requires "the knowledge the sweep applies to be anchored in one
versioned source with explicit staleness triggers — not restated across the skills that consume it."
The cross-vendor review raised this as the strongest argument against the re-derivation, and it is
right that the first draft neither cited nor reconciled it. Doing so here.

**The criterion holds. What satisfies it is a citation and a shared staleness trigger, not a shared
file.** The live catalog already states the idiom: "point-don't-copy — the full doctrine lives at the
cited URL, not restated here." Each rule carries a one-line decisive quote plus the official URL it
came from; the *anchor* is the official page, which is versioned by its publisher and cannot drift
from itself. A per-plugin materialized copy would not add anchoring — it would add a second thing to
keep in sync with the first, which is what ground-truth verification just showed the repository
cannot detect for this artifact.

**But the review found a real gap underneath the objection, and it is not the one it named.** The
four host plugins carry three different staleness idioms and one absence: `claude-config` and
`claude-memory` each ship a versioned `reference/criteria.md` with recheck triggers,
`docs-hygiene` repeats a "Recheck triggers" convention inline across its skills, and
`skill-quality:check` has **no criteria file and no staleness mechanism at all**. Landing a
doctrine-derived rule in a host with no staleness discipline is how the drift the Brief fears
actually happens — not through restatement, but through a rule nobody rechecks.

Three requirements follow, and they bind every calibration input:

1. **Every rule cites its source URL and carries the catalog's recheck triggers verbatim in
   meaning** — a new frontier model release, a change to the prompting-best-practices pages, a
   change to the Claude Code best-practices page. Same triggers, so one event fires all of them.
2. **A host with no staleness surface gains one before it receives a rule.** For
   `skill-quality:check` that is a prerequisite, not a nicety, and it is the cheapest place the
   Brief's criterion is genuinely at risk.
3. **The four rules are named as a family in one place** — the shipped catalog's own entry for the
   source — so a recheck of the doctrine enumerates its dependents instead of relying on someone
   remembering all four.

That is the anchoring the criterion asks for, at a cost the ground-truth evidence says the
repository can actually hold.

## Homing map — Phase 5, folded in

Assigned against the incumbents' actual bodies, not their listing descriptions — the evidence gap
the blind-derivation pass identified. **Two host plugins, not four.**

| D | Owner | Form it takes | Disposition |
|---|---|---|---|
| D1 | `claude-config` | new check I12 in `audit-instructions/reference/criteria.md` | `new-check` |
| D2 | `claude-config` | extends I9's Remediate line with the interface destination | `extend` |
| D3 | `claude-config` | new check beside I3, on the locality axis | `new-check` |
| D4 | `claude-config` | a stopping condition on I6 and I8 | `suppression-input` |
| D5 | — | none built | `deferred-with-trigger` |
| D6 | `claude-config` + `claude-memory` | I3's Remediate gains a destination-qualifying test and a move cost; the memory half joins the C3 revision | `extend` |
| D7 | `claude-memory` | one consolidated C3 revision: an auto-memory destination row, an `@path` non-deferring row, and a per-destination move cost | `extend` |

Both named plugins exist under `plugins/`. Every row names a skill directory that already exists.
No row reads TBD.

**`docs-hygiene` and `skill-quality` receive nothing, and the reasons are evidentiary rather than
tidy.** `skill-quality:check` declares "NO model invocation… reproducible in CI or a pre-commit
hook", and its entire relationship to frontmatter is presence, parse, name-match, character budget,
and git-stability — `argument-hint` is read by nothing in the plugin. A rule requiring a judgement
about representational equivalence would be the first non-reproducible check in a gate whose value
is that every check is reproducible. Every `docs-hygiene` trimmer already owns a stopping condition
shaped to its own content model: semantic-loss revert in `compress`, always-admitted categories in
`audit-noise`, fact ownership in `audit-derivability`, reasoning-stays-inline in `extract-ssot`.

**This also disposes of the review's synchronization objection.** The worry was four
independently-authored restatements in four hosts with three different staleness idioms and one
absence. There are two hosts, both already ship a versioned `reference/criteria.md` with recheck
triggers, and they already carry a reciprocal presence-gated invocation seam between them. The host
with no staleness surface receives nothing.

## `OPINION`-tier policy

This work is the first to populate the tier — the live catalog declares the `OPINION` authority
value and states "All eleven seeds are `ANTHROPIC-DOCS`", so no consumer has ever had to decide what
an `OPINION` finding means. Defining it is therefore this work's obligation, and the gate is where it
lands because five of the seven dispositions above rest on `OPINION` status.

The policy splits on what a rule *does*, because a single default is wrong for half of them.

**Emitting rules — those that produce findings.** The 80% claim, the S6 interface half, the S8
placement rule, the S10 artifacts claim.

- **Default enablement: off.** An emitting `OPINION` rule produces no finding on bare invocation.
- **Opt-in is explicit** — a named argument or configuration key, never a side effect of another
  setting.
- **Severity ceiling: `info`.** An unconfirmed practitioner preference cannot raise an `error` or a
  `warning` against a consumer's instruction corpus.
- **Never fix-applied.** `OPINION` findings are reported, never mutated automatically, regardless of
  the sweep's apply posture.

Rationale: shipping them enabled would let one practitioner's unconfirmed preference mutate a
consumer's instruction corpus under the same banner as documented doctrine. Dropping them instead
would violate the Brief's settled scope, which keeps every rule and marks the unbacked ones.

**Advice attached to a backed finding — the case the two-way split missed.** D2 is `OPINION`-tier
and lands as an extension of **I9's Remediate line**, and I9 is `ANTHROPIC-DOCS` and default-on. A
line inside a default-on check's remediation cannot itself be default-off without splitting that
check's output, so the emitting-rule policy above would make the merge impossible as specified.

The resolution is that **D2 does not emit anything.** I9 already fires on the artifact — an example
block pinning the model's approach — on officially-backed grounds. D2 changes only what the operator
is told to do about a finding that was going to be reported anyway. So:

- **The finding's enablement and severity follow the host check**, because the detection is the
  host's and is backed.
- **The `OPINION`-derived remediation is labelled inline as such**, so an operator can see which part
  of the advice rests on a practitioner's preference rather than on documentation.
- **It is never fix-applied**, which is the one clause of the emitting-rule policy that does carry
  over, and the one that actually protects the consumer's corpus.

The general rule: `OPINION` enablement attaches to *detection*, not to *advice*. Any future
`OPINION` content folded into a backed check is governed the same way.

**Withholding rules — those that suppress findings.** D4's carve-out is the only one today, and it
is `OPINION`-tier.

- **Default enablement: on.** A suppressor is enabled by default and disabled only by explicit
  opt-out.

**Discovery is part of the policy, not an afterthought.** A rule that is off by default, opt-in
through an unnamed mechanism, and capped at `info` is shipped-but-unreachable — real engineering
cost in Phase 8's gates and evals, and no consumer who does not already know it exists will ever
find it. The Brief's commitment to ship `OPINION` content rather than drop it is honored on paper
and broken in practice unless the content is discoverable. So:

- **Every run reports the tier's existence** — a single line naming how many `OPINION`-tier checks
  were available and not run, and the exact argument that enables them. It costs one line and turns
  an invisible feature into an offered one.
- **The enabling mechanism is named in the skill's own documentation**, not left to be inferred.

Raised by the cross-vendor review, which was right that the policy as first written made the tier
dead weight.

Rationale, and it inverts the case above. PLAN.md's risk table mitigates the High/High risk
"Detectors flag correct constraint as over-constraint" *with* D4's carve-out as a live suppression
input every trimming detector consults. Defaulting a suppressor off does not make the pass more
conservative — it deletes the mitigation and makes every trimming detector strictly **more**
aggressive on bare invocation, which is the exact failure the risk row exists to prevent. The
uniform "`OPINION` defaults to off" rule is correct for a rule that emits and inverted for a rule
that withholds. Caught by the blind-derivation reviewer; no prior document noticed it.

## D1 scope questions, answered

[official-corroboration.md](official-corroboration.md) parked three scope questions for this gate
rather than resolving them silently. Each is answered here.

- **Prompt-carrying configuration surfaces** — `routines`, `scheduled-tasks`, `goal`, `channels`,
  `statusline` (`official-corroboration.md:246-248`). **In scope for D1's inventory, out of scope
  for D1's conflict comparison, in this pass.** They can hold instruction text, so an inventory that
  omits them under-reports the surface; but their text is scoped to a single invocation rather than
  layered into every request, so a contradiction between one of them and `CLAUDE.md` is not the
  failure mode the memory doc's "Consistency" section describes. Recorded as an explicit exclusion
  with a trigger: promote to the comparison set if a consumer reports a conflict originating there.
- **Output styles** (`official-corroboration.md:197-203`). **In scope for both**, and a first-class
  D1 conflict source. They modify the system prompt directly, default to *removing* Claude Code's
  built-in software-engineering instructions, and `force-for-plugin` lets a plugin override the
  operator's own selection. A filesystem-walk inventory would miss the override entirely — which is
  itself evidence for the native-first inventory Phase 6 must clear.
- **The managed-policy tier** (PLAN.md Phase 10). **In scope, read-only, never remediated.** It
  loads before user and project scope and `claudeMdExcludes` cannot reach it, so a conflict with it
  is reported as "conflicts with org policy at `<path>`" and the lower surface is never proposed for
  edit on that basis. Absence of the path degrades cleanly.

### D1's detection rule is narrower than "two instructions differ"

Raised by the blind-derivation reviewer and adopted here, because D1 is now the deliverable's entire
payload and an over-broad scope would be the single most expensive error available.

`official-corroboration.md:208-212` records the official per-surface layering rules: `CLAUDE.md`
files are additive across levels; skills, subagents, and MCP servers override **by name**; hooks
merge. Where the layering rule already picks a winner, two differing instructions are not an
unresolved conflict — they are a resolved override, and flagging one is a false positive.

D1's detection rule is therefore: *two instructions conflict **and** the layering rule does not
already determine which wins.*

**Corrected while drafting Phase 6, because the first statement of this narrowing was wrong in a way
that would have gutted the payload.** It said the comparison set was the `CLAUDE.md` family, hooks,
and output styles, and excluded skills, subagents, and MCP servers wholesale on the grounds that
they "override by name". That misreads the rule. Override-by-name resolves a collision between two
entities *sharing a name* at different scopes — the shadowed one is inert, not conflicting. It says
nothing about a skill body contradicting `CLAUDE.md`, which is **the source article's own headline
example**: "leave documentation as appropriate" against "DO NOT add comments", with the system
prompt, a skill, and the user request clashing in one request. Excluding skill bodies would have
excluded the failure D1 exists to detect.

The exclusion is therefore narrow and specific, not surface-wide: a same-named skill, subagent, or
MCP server shadowed at a higher-precedence scope is **not** a conflict, because exactly one is live.
Everything else that can hold instruction text is in the comparison set.

The same page supplies D1's other primary carve-out: for `CLAUDE.md` conflicts, "Claude uses
judgment to reconcile them, with more specific instructions typically taking precedence" — so a
more-specific instruction narrowing a broader one is lawful, not a defect.

Task #19 owns the rule; [checks-and-sweep.md](checks-and-sweep.md) states it in full.

## Corrections this gate forces on upstream documents

The blind-derivation pass found defects in the documents this gate reads. They are recorded here and
tracked as work rather than silently fixed, because two of them weaken arguments PLAN.md makes.

1. **PLAN.md's "two documents agree" argument is an axis conflation.** `coverage-matrix.md` measures
   *who enforces a rule*; `official-corroboration.md` measures *whether the rule is true*. A rule can
   be fully confirmed and still be the largest gap — S3 is exactly that, and S7 is the mirror image.
   The two are also not independent inputs: both descend from `article-sections.md`. The gate's
   conclusion survives on the per-row evidence in the disposition table above, but the agreement
   argument does not support it and must be struck from PLAN.md.
2. **`features-overview` covers D3 and D6 substantively, not only D7 — and the S8 entry needs
   splitting rather than flipping.** Resolved here, because D3's enablement turns on it. The page
   states *surface routing* — a three-way `CLAUDE.md` versus `.claude/rules/` versus skills table,
   the 200-line rule, and the verbatim request-versus-enforcement boundary. It does **not** state
   *definition-site locality*: nothing on it says an instruction belongs next to the thing it
   governs. D3's axis is locality, so **S8's routing half is confirmed and its locality half stays
   unconfirmed**, and D3 ships `OPINION`-tier and default-off. The corroboration entry should record
   both halves instead of one verdict for both. The effect on D6 is different and simpler: the
   200-line rule and "move reference content to skills or split into `.claude/rules/` files" are
   direct backing, which is part of why D6 is default-on.
3. **The `ANTHROPIC-DOCS` authority token is asserted but never recorded.** The corroboration table
   uses prose verdicts ("Confirmed", "Partly confirmed", "Split") and never writes the token, yet
   PLAN.md asserts S3 is "`ANTHROPIC-DOCS`-backed". S14 is the case that breaks: identical
   evidentiary status to the S10 artifacts claim, but never tagged `OPINION`. The catalog's axis
   values must be written into the corroboration table per row.
4. **S5's `COVERED` contradicts S13's remainder.** `coverage-matrix.md:28` marks S5 covered by I6+I8
   while `:36` says the missing carve-out leaves "a trimming pass no principled stopping point". A
   trimming pass without a stopping condition is not covered.
5. **`/doctor` is described as "(built-in, alias `/checkup`)"** in `coverage-matrix.md:12`, but
   `official-corroboration.md:78` records it as a bundled skill as of v2.1.205. The `/checkup` alias
   appears in no quoted source and must be verified against a fetched page or removed.
6. **Numeric and sanity-check drift.** PLAN.md carries both "178 skills" and 181; and Phase 1's
   Outcome says "All eleven slugs are recorded" under a check that was deliberately widened to
   fourteen. The outcome text does not satisfy its own check.

## The design tier, actually re-derived

`design-resolution.md:104-106` says the Tier A classification is contingent on this gate and must be
re-derived if the escalation fires. It fired, so the label is not carried forward on its old
grounds — it is recomputed here.

**The two signals that originally carried it are gone.** There is no versioned criteria catalog
consumed by more than one plugin, and there are no new checks across four plugins — there is one new
check inside an existing catalog, plus refinements to rules the host plugins already own.

**Two different signals carry it now.**

- **A new component that mutates instruction corpora.** The sweep is new surface, and it is
  fix-capable against a repository's own instruction files. Blast radius is unchanged at HIGH: every
  plugin and skill in the marketplace is a target, and a bad rule applied broadly is the plan's
  own Low/Critical risk row.
- **Cross-plugin integration through the invocation seam.** Dropping the shared catalog removed a
  shared *artifact*, not the integration: the sweep still dispatches sibling plugins, still needs
  presence gating and documented fallbacks per `docs/conventions/seam-phrasing/`, and four plugins
  still receive rules that must be independently useful.

**Tier A holds, on new grounds.** The consequence matters: `design-resolution.md`'s gate says a
Shape 1 or Shape 3 outcome would warrant a separate `/planning:design` pass for the catalog's own
contract. No such pass is warranted, because there is no new contract — the design work that
remains is D1's detection rule, the re-run contract, and the sweep's dispatch design, all already
sequenced as phases.

## Deferred tool loading — a remainder that is not D6's

`coverage-matrix.md:30` states two remainders under S7, and only one of them is about
progressive-disclosure destinations. The second — "deferred tool loading is unowned" — is a bare
`GAP` by the same logic that made D1 a detector, and folding it silently into D6's disposition would
have buried it. Raised by the cross-vendor review; recorded here as its own item.

**Disposition: out of scope for this pass, with a trigger.** Deferred tool loading is governed by
tool-search configuration and MCP server exposure — `official-corroboration.md:155-163` places it at
`mcp#scale-with-mcp-tool-search`, with `ENABLE_TOOL_SEARCH` as the control. That is a
context-*budget* surface, not an instruction surface, and this pass audits instruction surfaces.
An existing plugin already owns the adjacent concern (`mcp-tools:audit`).

**Trigger:** if the pass's scope widens from instruction content to context budget, or if
`mcp-tools:audit` is found not to cover tool-search configuration, this becomes a check and needs an
owner. Verifying that second condition is a work item, not an assumption — it is exactly the
"negative claim about a body nobody read" failure the blind-derivation pass called out.

## What this gate does not decide

- D1's detection rule, remediation, and false-positive carve-out — Phase 6, task #19.
- The one surviving seam question for D4's carve-out — Phase 2, task #36.
- The re-run contract's identity function and tolerances — Phase 4, task #35.
- Naming — Phase 6, under the fixed verb meanings.

## Independent verification

Phase 2.5 carries no `Review:` tag of its own, but its verdict rewrites the phases that do, and it
was produced by the session that proposed it. Two independent passes therefore gate it, both
recorded here on completion.

1. **Blind derivation — complete.** A fresh-context agent derived dispositions for D1–D7 from
   `article-sections.md`, `coverage-matrix.md`, `official-corroboration.md`, `skill-inventory.md`,
   and PLAN.md's Phase 2.5 text alone, never shown the table above. It also read `criteria.md`
   unprompted, to judge the incumbent's real detection space rather than the coverage matrix's
   description of it.

   **It reached the same count — one detector — and the same disposition for D1, D2, D4, and D5.**
   It differs on homing: it routes D3, D6, and D7 to `claude-config:audit-instructions` check I3
   (with `claude-memory:audit` taking only D7's memory half), on the grounds that all three answer
   one question — "is this content in the right home" — and that I3 already detects and remediates
   exactly that shape. It argues the D3/D6/D7 split is an artifact of the source article's section
   numbering rather than of detection space. **That disagreement is unresolved in the homing table
   above and is being decided against the incumbents' actual bodies, not their descriptions.**

   **Its independence caveat, recorded because it is correct.** The blind pass cannot confirm the
   count, because PLAN.md pre-states it: the gate demotes D2–D5 by default and promotion requires "a
   written reason" against no stated standard, so the gate as written cannot fail. What the pass
   confirms is narrower — the conclusion holds on the per-row evidence, while two of the reasons
   PLAN.md gives for it do not (corrections 1 and 2 above).

   **It also found that most `GAP` and `PARTIAL` verdicts are negative claims about bodies nobody
   read** — `coverage-matrix.md:13-18` verifies most incumbents by "Skill description read this
   session". D2's entire remainder is an assertion about `skill-quality:check`'s contents drawn from
   a one-line listing description. That evidence gap is being closed before the homing table is
   final.
2. **Cross-vendor architecture review — complete.** The written gate reviewed through
   `codex:codex-rescue` (codex-cli 0.145.0), artifact-first, asked seven adversarial questions
   including "what is the strongest argument this entire re-derivation is wrong". It returned eight
   ranked defects. **It did not dispute the count, the escalation, or the catalog deletion** — its
   attack was on the reasoning, and it was right twice at CRITICAL:

   - The re-derived shape contradicted PLAN.md's settled "one versioned source... not restated
     across the skills that consume it" criterion, uncited. Reconciled above, and the reconciliation
     surfaced the real underlying gap: `skill-quality:check` has no staleness surface at all.
   - D2's demotion did not satisfy this gate's own stated test — `coverage-matrix.md:29` describes
     the same "no incumbent does this" shape that made D1 a detector, and the demotion actually
     rested on evidentiary tier, a different axis. The two-test correction above is the response.

   Four further findings are absorbed above: the disposition vocabulary was incomplete and now says
   so; the `OPINION` tier was unreachable as specified and now carries a discovery requirement; the
   design tier was relabeled rather than re-derived and is now recomputed; and D6's disposition had
   silently swallowed the "deferred tool loading is unowned" remainder, which is now its own
   recorded item. Its challenge to the sweep's status as a component rather than a runbook is
   answered above, in the re-derived shape.
