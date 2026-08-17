# Persisting findings: this plugin's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
an ai-slop run decides for itself and cites the contract for the rest. Where the two disagree, the
contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination reports success while
the consumer never scans that path.

## Where the file goes

Resolve per the contract "Where the file goes": run the WHOLE rung order (never only its
documented default), take the non-interactive collapse for the rungs that confirm or ask, honor
the self-ignore guard including its invalid cases, and prove the destination is outside tracked
space before writing (the contract and its topic-docs binding own the proof; a destination that
cannot be proven is reported and not written to).

File name: `${TS}-ai-slop.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free, Windows-safe).
Never overwrite: when the path exists, take `-2`, `-3`, the smallest free integer.

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim.
- **`Location`** is `<repo-relative path>:<line>` from the detector's `file=` and `line=` fields;
  never the file alone.
- **`Surface(s)`** is `ai-slop:audit`.
- **`Finding`** leads with the qualified rule id and the detector's `fired=` condition in the
  run's own values (the zero-tolerance marker, or the density/threshold/hits/words tuple), then
  the excerpt. No rubric reasoning in the cell.
- **`Action`** states the remediation shape the crosswalk row implies: the reworded sentence for
  style rules (judgment; the fix action owns it), the parameter strip for
  `rule-utm-params`, the delete-or-source decision for the two IMPORTANT residue rules.
- **Cell-escape** `Finding` and `Action` per the shape's rule (`\|`, newlines to spaces) — the
  detector's excerpts already replace `|` with `/`, but the composed cells must be re-checked.
- **`Tier`** is LOOKED UP from the rule's crosswalk row, then mapped to the consuming project's
  severity vocabulary when it defines one (the contract's consumer-precedence rule).
  **`Confidence`** is `high` on every emitted row: a deterministic detector fired.

**Only script-rule findings enter the file.** Judgment-rubric findings go to the human report
only (the V1 relay boundary; a rubric verdict has no crosswalk row to look a tier up from).
Every cell describes a finding the detector actually emitted this run; never compose an
illustrative row or carry one forward.

## Surfaces, and when the file is written at all

`## Surfaces` names `ai-slop:audit` once, states what was scanned (target set, files scanned),
and carries the declined counts per rule id straight from the detector's `Summary` rows
(`declined=` and `disabled=`), in the section's line form. Omit `tier:`, `## By dimension`, and
`## Unparsed` (one dimension; nothing unparsed).

- Findings to emit → write.
- Files scanned, zero findings → write anyway with the empty `## Findings` header: coverage is
  the payload.
- Nothing scanned (empty target set, everything excluded) → write nothing; say so in the report.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After this skill's own `fix` action completes, re-run the detector and emit a
fresh file so no stale findings file survives its own remediation.
