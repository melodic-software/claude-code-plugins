# Persisting findings: this skill's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
an `audit-noise` run decides for itself and cites the contract for the rest. Where the two
disagree, the contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination reports success while
the consumer never scans that path.

## This does not loosen the read-only contract

The skill's read-only hard rule still holds, and it is stated there in the terms this file needs:
the audit never mutates an AUDITED DOCUMENT, and a findings artifact is not such a mutation. A
findings file is a **proposal artifact** — it reaches `review:fanout`'s `fix` action, which is
itself human-gated. Persisting is therefore opt-in: a bare invocation reports and stops, exactly
as before. Never describe the findings file to an operator as a treatment that has been applied.

## One rule reaches the relay

Of this skill's six shapes, exactly one carries a severity-crosswalk row —
`docs-hygiene/audit-noise/rule-negation-without-positive`. The other five have no row, so they
have no tier to look up and never enter the file: the contract's "a rule failing the admission
test is not a row with a missing cell — it is a rule this contract does not admit". They are
counted per rule id in `## Surfaces` with `reason=no-severity-crosswalk-row`, so the boundary is
visible rather than silent, and they still reach the human through the ordinary report.

## Where the file goes

Resolve per the contract "Where the file goes": run the WHOLE rung order (never only its
documented default), take the non-interactive collapse for the rungs that confirm or ask, honor
the self-ignore guard including its invalid cases, and prove the destination is outside tracked
space before writing (the contract and its topic-docs binding own the proof; a destination that
cannot be proven is reported and not written to).

File name: `${TS}-audit-noise.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free, Windows-safe).
Never overwrite: when the path exists, take `-2`, `-3`, the smallest free integer.

## Compose by script, not by hand

Once the destination is resolved and the contract fetch succeeded, run
`${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh --from <detect output file> --out <resolved path>`.
A repo-wide run produces thousands of rows; composing them in prose is exactly the hand-transform
the fleet's scripting discipline forbids, and the script owns the mechanical half: cell assembly,
escaping, the tier lookup (a mirror of the crosswalk — the crosswalk row is authoritative), rank
ordering, `Location` relativization, the non-overwrite suffix, and the `## Surfaces` counts. What
stays with the model is everything before the script (rung-order resolution, the fetch-and-refuse
gate, the self-ignore guard) and everything after it (reading the written file's head to confirm
shape, and severity-vocabulary mapping when the consuming project defines its own — edit the
written file's `Tier` cells per the contract's consumer-precedence rule).

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim. With no branch resolvable the script
  refuses rather than writing a file the relay can never match.
- **`Location`** is `<repo-relative path>:<line>` from the detector's `File:` and `Finding line:`
  fields; never the file alone. It names the DETECTION site and is never retargeted.
- **`Surface(s)`** is `docs-hygiene:audit-noise`.
- **`Finding`** leads with the qualified rule id and the condition that fired in the run's own
  values (`cue="Never", positive-clauses=0`), then the excerpt.
- **`Action`** states the remediation the crosswalk row implies: rewrite to the positive target,
  keeping the negation only where the positive form loses the constraint and then pairing the two
  in one sentence.
- **Cell-escape** `Finding` and `Action` per the shape's rule (`\|`, newlines to spaces). This
  detector reads DOCUMENTS, so excerpts carry markdown table pipes as a matter of course — the
  escape is load-bearing here, not defensive.
- **`Tier`** is LOOKED UP from the rule's crosswalk row (`SUGGESTION`), then mapped to the
  consuming project's severity vocabulary when it defines one. **`Confidence`** is `high` on
  every emitted row: a deterministic detector fired.

## Surfaces, and when the file is written at all

`## Surfaces` names `docs-hygiene:audit-noise` once and carries the declined counts per rule id.
Omit `tier:`, `## By dimension`, and `## Unparsed` (one dimension; nothing unparsed).

- Findings to emit → write.
- Files scanned, zero findings → write anyway with the empty `## Findings` header: coverage is
  the payload.
- Nothing scanned (empty target set, everything excluded) → write nothing; say so in the report.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After the author applies treatments, re-run the detector and emit a fresh file
so no stale findings file survives its own remediation.
