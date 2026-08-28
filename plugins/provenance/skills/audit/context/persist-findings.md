# Persisting findings: this plugin's read of the detector-findings contract

**Resolve the producer contract before the first write.** It owns the shape's authority, where
the file goes, the producer-computed fields, the coexistence obligations, the self-ignore guard,
and what a minimal producer may omit. This file adds only what a provenance run decides for
itself and cites the contract for the rest. Where the two disagree, the contract wins and this
file is the defect.

Resolve it in this order:

1. **The `review` plugin's bundled copy, when that plugin is installed.** It ships
   `reference/findings-file-shape.md`, which owns the shape the fix action consumes, and its
   `skills/fanout/` tree owns the merge-set rules. Read those files directly. This rung works
   offline, which is the point of putting it first.
2. **The publisher's raw URL**, when `review` is not installed:
   <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
3. **Neither reachable → do not write.** Report that the destination and the guard could not be
   resolved from their owner, and say the run is report-only. Inventing a destination reports
   success while the consumer never scans that path.

Rung 1 exists because rung 2 alone made every offline run report-only and pointed a portable
plugin at one organization's URL. The gate is installed-ness of `review`, never a marketplace
id. Note what rung 1 does and does not give you: the file SHAPE and the merge rules, which is
what composition needs. If the consuming project defines its own severity vocabulary, that
mapping is still yours to apply (see `Tier` below).

## Where the file goes

Resolve per the contract's "Where the file goes": run the WHOLE rung order, never only its
documented default; take the non-interactive collapse for the rungs that would confirm or ask,
since this detector cannot ask; honor the self-ignore guard including its invalid cases; and
prove the destination is outside tracked space before writing. A destination that cannot be
proven is reported and not written to.

**This resolution is model work and stays model work.** It reads prose — a `CLAUDE.md`
declaration, a configured `memory_dir` — and prose inference is not reasoning-free, so it
cannot move into `emit-findings.sh` without breaking the plugin's script/model split. A bash
implementation would either violate that split or silently collapse to the documented default,
which is the one failure mode nothing reports.

File name: `${TS}-provenance.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free, Windows-safe).
Never overwrite: when the path exists, the script takes `-2`, `-3`, the smallest free integer.

## Compose by script, not by hand

Once the destination is resolved and the contract resolution succeeded, run:

```bash
"${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh" --report <report sidecar> --out <resolved path>
```

The script owns the mechanical half: relay-eligibility filtering, cell assembly and escaping,
tier lookup (a mirror of the crosswalk, which stays authoritative), rank ordering, the
non-overwrite suffix, the `## Unparsed` appendix, and the `## Surfaces` counts. What stays with
the model is everything before the script — rung-order resolution, the contract resolution
above, the self-ignore guard — and everything after it: read the written file's head to confirm
the shape, and map `Tier` to the consuming project's severity vocabulary when it defines one,
editing the written file's `Tier` cells per the contract's consumer-precedence rule.

Hand-compose only when the script cannot run (no bash, or no jq), following "What each cell
says" below.

## The relay boundary, and why the script enforces it

**Only fingerprint-confirmed copy findings and the two deterministic stamp rules enter the
file.** Judgment verdicts — `source-fetched-similar`, `llm-suspected`, and the neutral
`not-found` outcome — go to the human report only. They have no crosswalk row to look a tier up
from, and a relay row is an instruction to a remediation surface, not a place to record a
suspicion.

The script applies this filter itself rather than trusting the sidecar to arrive pre-filtered,
and it counts what it withheld in `## Surfaces` rather than dropping it. Two consequences worth
knowing before you read a written file:

- **Tier names of withheld findings never appear in the file.** A relay file is the apply
  action's input, and naming a tier this producer deliberately withheld invites a consumer to
  act on it. The count is there; the vocabulary is not.
- **A finding the script cannot map to a relay rule lands in `## Unparsed` verbatim.** That is
  the honest outcome for a malformed or future record, and it is never a silent drop.

Every cell describes a finding this run actually produced. Never compose an illustrative row,
and never carry a row forward from a previous run.

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim. The script quotes it when a plain YAML
  scalar would misparse (`#foo` reads as a comment; `no` reads as false), because the consumer
  admits a file on an exact branch match and a misparse silently drops every finding for it.
- **`Location`** is `<repo-relative path>:<line>`; the line is the finding's `line`, or its
  `span.start_line` for a copy finding. For a `fingerprint-confirmed` copy that start line is
  the module's exact matched span, not the nomination's approximation, which is what makes the
  fix fenceable.
- **`Surface(s)`** is `provenance:audit`.
- **`Finding`** leads with the qualified rule id, then the fired condition in this run's own
  values: matched span words, containment and the source URL for a copy; the stamp date, the
  window and days over for an expired stamp. No rubric reasoning in the cell.
- **`Action`** states the remediation shape the crosswalk row implies. None of the three rules
  is auto-applicable: a copy is remediated through `/provenance:audit fix`, whose disposition
  choice, semantic-diff guard and pointer-liveness checks are producer-owned; an expired stamp
  is repaired by re-deriving the record against its live basis; a trigger-less stamp is
  repaired by writing the observable event that obliges re-derivation.
- **`Tier`** is LOOKED UP from the rule's crosswalk row, never chosen per finding, then mapped
  to the consuming project's severity vocabulary when it defines one.
- **`Confidence`** is `high` on every emitted row: each is a deterministic rule that fired.
  Confidence is confidence-of-realness, never confidence in the fix; the fix judgment is said in
  `Tier` and in the `Action` wording, never by downgrading this field.

## Surfaces, and when the file is written at all

`## Surfaces` names `provenance:audit` once, states the corpus size scanned, and carries the
relay-eligible count plus the withheld and unmapped counts. Omit `tier:` and `## By dimension`:
nothing here computes a run-size value, and the relay carries one dimension.

- Findings to emit → write.
- Files scanned, zero relay-eligible findings → write anyway, with the empty `## Findings`
  header. Coverage is the payload, and a clean corpus is a result.
- Nothing scanned (empty target set, everything carved out) → write nothing; say so in the
  report, and name the carve-outs that emptied the set.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After this skill's own `fix` action completes, re-run the audit and emit a
fresh file, so no stale findings file survives its own remediation.
