# Detector findings — reaching the apply relay from outside `review:fanout`

Owner doc for **how a component that is not `review:fanout` persists findings that the fanout `fix`
action will consume**. One rule: a producer writes a file conforming to the findings-file shape into
the current branch's findings directory, and nothing else. No fanout edit, no registration, no
dispatch wiring.

The shape is owned by
[`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md)
"Findings-file shape (stable contract — the fix action consumes it)". **This doc never restates it.**
What this doc owns is everything the shape alone does not settle: which fields a non-fanout producer
must compute for itself, what coexistence between producers means, and where the boundary sits.

This is a stub, published deliberately ahead of its depth. `PLUGIN-PHILOSOPHY.md`
[Convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) — "A new cross-plugin
convention lands in an owner doc **before a second plugin adopts it**" — is a deadline, not a licence
to author late, and the first detector pilot is itself that second adopter. Depth trails the pilot
because the pilot is what produces the evidence; the deadline is why the stub cannot.

## Why the contract is format-only

Nothing authenticates the writer. The `fix` action locates its input purely by frontmatter — files
declaring `type: review-findings` whose `branch:` matches the current branch exactly — never by
provenance. That is not an oversight and it is the cheapest wiring path in the fleet: a skill, a
script, a hook, or an agent all reach the apply relay by writing one file.

It matters because the fleet's gap is **detectors, not apply capability**. Deterministic detectors
exist and produce real findings; what they lack is a route to a remediation surface. Conforming to a
file format is that route.

## Where the file goes

The destination is a **memory-tier, concern-scoped** location, and a producer resolves it through the
same binding the consumer does:
[`plugins/review/reference/topic-docs.md`](../../../plugins/review/reference/topic-docs.md)
"Resolution (the contract's five-rung order, earlier wins)", which
[`SKILL.md`](../../../plugins/review/skills/fanout/SKILL.md) "Shared inputs" names as what
`review:fanout` resolves through. The two texts state different rung counts — `SKILL.md` inlines the
rungs it operates on — and the non-interactive rule below is what makes them coincide. Naming the
binding by its repo path is the point of this section: `review:fanout` reaches it through a
`${CLAUDE_PLUGIN_ROOT}`-relative pointer no plugin outside `review` can expand, and it is the same
document either way.

What the binding leaves to a producer — consequences, not a second statement of its rules:

- **Run the rung order, not only its last rung.** Writing to the documented default when a higher
  rung resolved puts the file somewhere the `fix` action never scans, and nothing reports the miss —
  the configured `memory_dir` and the `CLAUDE.md`-declared location are exactly the cases that fail
  silently.
- **Take the non-interactive collapse.** A producer that cannot ask the user or persist config — a
  headless detector cannot — resolves the rungs that confirm or ask through the
  [topic-docs convention](../topic-docs/README.md) "Non-interactive / forked mode". Inventing an
  answer to those rungs instead resolves to a directory the consumer never reaches.
- **The directory never proves ownership.** What proves a file is this branch's is its own `branch:`
  frontmatter, never the directory it sits in — the binding's slug rule says why.
- **The self-ignore guard is owed, not re-derived** — including the convention's invalid-root rule,
  which stops the guard from healing into a consumer's root `.gitignore`. Skipping it commits
  findings that are meant to stay checkout-local.

## Boundary

This doc owns the **producer-side contract** for non-fanout findings. It does not own:

- **The findings-file schema.** Owned by `default-mode.md` "Findings-file shape". Pointer, never a
  copy — a second statement of a table is a second thing to drift.
- **The consumer algorithm.** How the merge set is built, subtracted, deduplicated, and applied is
  owned by
  [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md)
  "Step 1: Build the merge set". A producer never needs to read it; it is named here so a reader
  chasing consumption behavior lands in one place.
- **Normalization and ranking.** The five-stage pipeline in
  [`findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md)
  is fanout's own internal reduction. A detector emits final values, not pipeline inputs.
- **Whether a detector should exist.** Candidate selection, guardrail class, and promotion are the
  `autonomy` plugin's routine-catalog concern.
- **Findings that never reach a relay.** A component that only reports to a human is out of scope;
  this contract begins at the decision to persist.

## The four producer-owned fields

A detector has no severity crosswalk, no confidence filter, and no normalization stage behind it.
These four are therefore computed by the producer, and each has a failure mode that is silent:

1. **`Tier` is machine-computed, never guessed.** Derive it from what the detector actually knows —
   the rule that fired, its class, its blast radius — and use the same derivation for every finding
   of that class. A detector emitting a hand-picked tier per run makes rank order meaningless across
   runs. The **vocabulary** is not this doc's to define: it is owned by
   [`plugins/review/context/severity.md`](../../../plugins/review/context/severity.md) "Severity
   tiers", whose consumer-precedence rule binds a producer too — when the consuming project defines
   its own severity vocabulary, map to the project's tiers rather than the baseline's. A detector
   emitting a vocabulary of its own invention is non-conforming.
2. **`Confidence` is `high` or OMITTED — never `low`.** The enum is defined by
   [`severity.md`](../../../plugins/review/context/severity.md) "Confidence axis", which already
   states the trap — `unscored` means "absence of a score is NOT low confidence". The *consequence*
   is what makes `low` actively harmful: the rank order is `high` > `medium` > `unscored` > `low`
   ([`findings-normalization.md:72`](../../../plugins/review/skills/fanout/context/findings-normalization.md)),
   so emitting `low` to express uncertainty ranks the finding *below* saying nothing at all. A
   deterministic detector that fired is `high`; anything less certain omits the field.
   **`Confidence` is confidence-of-realness, not confidence in the fix.** A detector can be certain a
   defect is real while its remediation needs human judgment; say that in `Tier` and in the `Action`
   wording, never by downgrading `Confidence` — that would bury a real finding beneath one nobody
   reported.
3. **`Location` is a repo-relative `file:line`.** The relativization rule belongs to the shape —
   `default-mode.md` "Findings-file shape" states it. What is producer-specific is the reason it is
   not optional: the fix action fences each remediation to its finding's `Location`, and an absolute
   path is not portable to the checkout that applies the fix.
4. **Cell escaping is the producer's job.** Apply `default-mode.md`'s "Cell-escaping rule (required —
   the fix action parses this table)" as written there. It is called out here, without restating the
   characters, because detector output routinely contains pipes — shell pipelines, type unions, regex
   alternation — making this the single most likely way a first detector ships a file that parses
   *wrong* rather than not at all.

## Coexisting with other producers

Producers share one directory and the consumer merges across all of them —
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1: Build
the merge set" owns how. Three obligations fall on a producer:

- **Write your own file. Never append into another producer's.** Appending would need a
  write-ordering and locking convention that does not exist, and a partial write corrupts a file
  another producer owns.
- **Name yourself in `Surface(s)`.** Rows that match exactly are collapsed into one naming every
  contributor; that collapse is only legible if each producer identified itself.
- **Expect near-duplicate rows to survive.** Cross-producer matching is deliberately narrow, so do
  not pre-deduplicate against another producer's output — you would be guessing at a defect you did
  not detect.

## Emitting more than once

An apply marks the files it consumed and the consumer subtracts them —
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 5" owns
the ledger. What binds a producer is one rule: **a detector re-runs and writes what it currently
finds; it never replays.** Re-emitting a stale file re-injects findings that may already be fixed.
How the ledger identifies what an apply consumed is "Step 5"'s to own and may change there; a
producer owes the rule regardless and never leans on the ledger to catch a replay.

## What a minimally conforming producer may omit

The admission test is stated by
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1" — meet
it and you are consumed. Beyond it, the coverage fields (`tier:`, `## By dimension`, `## Unparsed`,
`## Surfaces`) are required of `review:fanout`'s own writer to keep its report honest; a detector
with no analogue may omit them. **Omit rather than fabricate** — an invented `## Surfaces` line
asserts coverage that was never attempted, which is the failure that field exists to prevent. `date:`
is expected of every producer: it is the only record of when the detector actually ran, and a
consumer weighing findings against a moving tree needs it.

## Liveness

A detector that persists findings still owes the
[liveness-assertion contract](../liveness-assertion/README.md) "Core contract": fail loud, or publish
to an agent-readable channel. Writing a conforming findings file satisfies the second limb —
the file *is* the agent-readable channel, and the `fix` action is the agent that reads it. A detector
that writes nothing, reports green, and had findings satisfies neither.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A persisted file conforms to the findings-file shape | **Deterministic when built** — frontmatter keys and table columns are mechanically checkable. **Buildable now**: the first producer exists, so a gate has something to run against. Still unbuilt. |
| `Confidence` is `high` or omitted, never `low` | **Deterministic when built** — a literal-value check. Folded into the same gate, and equally buildable now. |
| `Tier` is machine-computed rather than hand-picked | **Reasoning-only** — the derivation lives in the producer's own logic and no artifact records it. |
| A producer's coexistence behavior (own file, self-named surface) | **Detect-then-judge** when built — appending into another producer's file is detectable; whether a `Surface(s)` value identifies the producer usefully is judgment. |

**This stub still defers all mechanical enforcement**, but no longer for want of a subject. Recorded
with event triggers rather than dates:

- **Recheck trigger (conformance gate) — FIRED.** `mutation-testing:audit` is the first detector to
  reach `main` with a persist path, so a gate now has a real emitter to check rather than a fixture.
  What that unblocks: the shape and `Confidence` judgments above are both a mechanical read of a file
  this repository can produce on demand. No gate is written here — naming the trigger as fired is
  what stops the deferral from reading as permanent.
- **Recheck trigger (this doc's depth)** — the pilot completes, or a second producer adopts the
  contract, whichever comes first. Either produces the evidence the stub was published without.
  Partially met: the pilot has produced its first evidence, including one gap the contract does not
  address — a producer whose remediation site is not its `Location` (#2681).

## Adopters

An **adopter** is a producer outside `review:fanout` that conforms to this contract. A row asserts
that the producer conforms today — **tabled only once it actually does**, because tabling a planned
adopter asserts what a reader cannot rely on.

| Producer | Status | Notes |
|---|---|---|
| `mutation-testing:audit` | Conforming, opt-in | The first detector pilot. Persists surviving mutants behind `--persist-findings`; bare invocation still reports and stops. Computes `Tier` from the Phase 4 verdict class and emits `Confidence: high` only. Omits `tier:`, `## By dimension`, and `## Unparsed` as a detector with no analogue for them; keeps `## Surfaces`, which is the whole payload of a run that examined mutants and found nothing. Carries one known limitation this pilot surfaced: a mutation finding's remediation site is its covering test, not its `Location`, so a consumer fencing to `Location` cannot reach the target (routed to #2681). |

`review:fanout` is not an adopter and is deliberately absent from the table: it is the **reference
writer** whose file format this contract points at, and it sits on the other side of the boundary
this doc draws.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

## External authority

- [`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md) — the findings-file shape this contract points at and never copies.
- [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) — the consumer algorithm, including merge-set construction and consumption marking.
- [`plugins/review/context/severity.md`](../../../plugins/review/context/severity.md) — the severity-tier and confidence vocabularies a producer emits, and the consumer-precedence rule that overrides the baseline.
- [`plugins/review/skills/fanout/context/findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md) — the rank order that makes `low` worse than omission.
- [`plugins/review/reference/topic-docs.md`](../../../plugins/review/reference/topic-docs.md) — the findings-location binding `review:fanout` resolves through, carrying the rung order, branch sub-path, slug rule, and guard a producer therefore never restates.
- [`docs/conventions/topic-docs/`](../topic-docs/README.md) — the tier semantics, guards, and invalid-root rule that resolver implements; not itself the pointer for where a producer writes.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` — tier vocabulary and routing rule.
- [`liveness-assertion`](../liveness-assertion/README.md) — the fail-loud-or-agent-readable contract a detector satisfies by persisting.
- [`PLUGIN-PHILOSOPHY` Convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) — one owner doc per shared concern, and the before-a-second-adopter deadline this stub answers.
