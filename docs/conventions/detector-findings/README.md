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
   runs.
2. **`Confidence` is `high` or OMITTED — never `low`.** This is the rule a detector author will get
   wrong, because it inverts the intuition. The rank order is
   `high` > `medium` > `unscored` > `low` ([`findings-normalization.md:72`](../../../plugins/review/skills/fanout/context/findings-normalization.md)),
   and absent confidence resolves to `unscored`, which ranks **above** `low`. `:62` states it
   directly: "Absent confidence ≠ low." So emitting `low` to express uncertainty ranks the finding
   *below* saying nothing at all. A deterministic detector that fired is `high`; anything less
   certain omits the field.
3. **`Location` is a repo-relative `file:line`.** Relativize before writing — strip the repo root,
   replace the home directory with `~`. An absolute path is not portable across the checkout that
   applies the fix, and the fix action fences each remediation to its finding's `Location`.
4. **Cell escaping is the producer's job.** Inside `Finding` and `Action` cells, write a literal pipe
   as `\|` and replace newlines with spaces. Detector output routinely contains pipes — shell
   pipelines, type unions, regex alternation — and an unescaped one splits the row into phantom
   columns that the fix action misreads. This is stated in `default-mode.md` as part of the shape;
   it is repeated as a *pointer* here because it is the single most likely way a first detector
   ships a file that parses wrong rather than not at all.

## Multiple producers, one directory

Producers coexist. The branch findings directory holds every producer's file, and the `fix` action
consumes the **merged set** of unconsumed conforming files for the exact current branch rather than
the newest one. Two consequences bind a producer:

- **Write your own file. Never append into another producer's.** Appending would require a
  write-ordering and locking convention that does not exist, and a partial write would corrupt a
  file another producer owns.
- **Name yourself in `Surface(s)`.** When two producers report the same defect at the same
  `Location` with identical `Finding` text, the consumer collapses them into one row naming both.
  That collapse is only legible if each producer identified itself.

Dedup across producers is **presence-only** — identical `Location` and identical `Finding` text, and
nothing looser. The tempting semantic key sits behind an LLM stage the `fix` action does not run, and
adopting it without the semantics would violate `findings-normalization.md`'s own ordering:
"Minimize FALSE-MERGE over FALSE-SPLIT — a false merge silently drops a real issue." A producer
should therefore expect near-duplicate rows to survive as separate rows, and should not try to
pre-deduplicate against another producer's output.

## Consumption is marked, and it is per file

An apply writes a record naming every file it consumed, and the consumer subtracts those files from
the next merge set. Two obligations follow for a producer:

- **A file is consumed once.** Re-emitting an unchanged file after an apply does not re-surface its
  findings unless the file name differs, and re-emitting under a new name re-injects findings that
  may already be fixed. A detector re-runs and writes what it currently finds; it never replays.
- **Do not write into the directory to signal anything but findings.** The frontmatter `type:` is the
  admission test; a file declaring `type: review-findings` will be parsed as findings.

## What a minimally conforming producer may omit

`type:`, `branch:`, and a parseable `## Findings` table are the admission test. `tier:`,
`## By dimension`, `## Unparsed`, and `## Surfaces` are required of `review:fanout`'s own writer to
keep its report honest about coverage; a third-party detector that has no analogue may omit them and
is still consumed. Omit rather than fabricate — an invented `## Surfaces` line asserts coverage that
was never attempted, which is the failure the field exists to prevent.

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
| A persisted file conforms to the findings-file shape | **Deterministic when built** — frontmatter keys and table columns are mechanically checkable. **Not built**: no producer exists yet, so a gate would have nothing to run against. |
| `Confidence` is `high` or omitted, never `low` | **Deterministic when built** — a literal-value check. Folded into the same unbuilt gate. |
| `Tier` is machine-computed rather than hand-picked | **Reasoning-only** — the derivation lives in the producer's own logic and no artifact records it. |
| A producer's coexistence behavior (own file, self-named surface) | **Detect-then-judge** when built — appending into another producer's file is detectable; whether a `Surface(s)` value identifies the producer usefully is judgment. |

**This stub defers all mechanical enforcement.** Recorded with event triggers rather than dates:

- **Recheck trigger (conformance gate)** — the first detector reaches `main`, giving a gate something
  to check.
- **Recheck trigger (this doc's depth)** — the pilot completes, or a second producer adopts the
  contract, whichever comes first. Either produces the evidence the stub was published without.

## Adopters

**A row is tabled only once a producer actually conforms.** Tabling a planned adopter would assert
what a reader cannot rely on.

| Producer | Status | Notes |
|---|---|---|
| `review:fanout` (default / run-everything modes) | Conforming (reference writer) | Owns the shape; the contract is its file format. Not a "detector", but the producer every other one is measured against. |

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

## External authority

- [`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md) — the findings-file shape this contract points at and never copies.
- [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) — the consumer algorithm, including merge-set construction and consumption marking.
- [`plugins/review/skills/fanout/context/findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md) — the rank order and the "Absent confidence ≠ low" rule that make `low` worse than omission.
- [`liveness-assertion`](../liveness-assertion/README.md) — the fail-loud-or-agent-readable contract a detector satisfies by persisting.
- [`PLUGIN-PHILOSOPHY` Convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) — one owner doc per shared concern, and the before-a-second-adopter deadline this stub answers.
