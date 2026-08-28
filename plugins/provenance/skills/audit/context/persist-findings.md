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
  the honest outcome for a malformed or future record. Nothing is dropped in silence: a record
  the script does map to a rule but cannot relay is counted in `## Surfaces` instead, and one
  bad record never refuses the sidecar or costs the well-formed findings beside it.

Those two clauses meet on one record: a judgment verdict carrying no rule id. They are ordered,
not opposed. **Withholding is decided on the declared tier, ahead of any rule lookup**, so that
record is withheld, and `## Unparsed` covers only what is unmappable for some OTHER reason — an
unknown rule id, a record that is not an object, a row too malformed to read. Keeping a
withheld verdict out of the
appendix does not drop it: `## Surfaces` carries it in the "Withheld from the relay: N judgment
findings" count, which is where the no-silent-drop guarantee is discharged for these records.
Routing one back into `## Unparsed` would print its tier name and its whole payload into the
apply relay's input, which is exactly what the clause above forbids. That is a leak, not a
restored guarantee — do not "fix" it that way.

`## Surfaces` counts the withheld separately by what they ARE. A copy finding declaring neither
`fingerprint-confirmed` nor a judgment verdict is not relay-eligible and gets its own count; it
is not a judgment finding, and counting it as one would tell a reader to look for it on the
human report, where it is not.

**Where the tier is read and which values name one answer opposite risks, and the script tunes
them separately.** Reading the wrong field is a silent drop; failing to see through a wrapper
around a real verdict name is a leak.

The KEY is an explicit allowlist — the top-level `tier`, and the whole of a top-level `verdict`
— because a miss THERE is a drop, which is worse than the leak it guards. This sidecar is
model-authored against no schema, and `tier` is already overloaded across it (the verdict tier,
and the crosswalk severity). A reader that took a `tier` key at any depth could not tell a
declared verdict from a nested mention of one, and withheld records that had declared
`fingerprint-confirmed` at the top level: no relay row, no `## Unparsed` entry, and a
`## Surfaces` count calling them judgment findings on a human report they were never on. Keys
are matched case-folded, but only at those two positions, so
`{"xref": {"TIER": "prior: not-found"}}` is the cross-reference it reads as.

A `verdict` is taken WHOLE rather than as `verdict.tier`, because a key named `verdict` is
already the declaration. `{"verdict": "not-found"}`, `{"verdict": ["not-found"]}` and
`{"verdict": {"result": {"tier": "llm-suspected"}}}` each say what
`{"verdict": {"tier": "not-found"}}` says, and reading only the `tier` child let all three past
the boundary — into a relay row when a stamp rule carried one, and verbatim into `## Unparsed`
when nothing else mapped the record. Whatever the outcome is declared inside, `searched` is read
inside it too, so a sidecar keeping the outcome and its surfaces together is not refused for
naming them where it declared the outcome.

The VALUE is read generously about its WRAPPER and exactly about the NAME. Every string anywhere
inside the declared value is a candidate, trimmed and case-folded, and it names a tier only when
it EQUALS one — so `"  not-found  "`, `["not-found"]`, `{"name": "llm-suspected"}` and
`"LLM-Suspected"` are all the verdicts they say they are, while a future `not-found-v2` is an
unknown tier rather than the verdict it happens to start with. A valid rule id sitting beside a
verdict does not readmit it either.

Free text in a tier field therefore names no tier, which is the same answer this producer
already gives a verdict name spelled in a `note`. It has to be: a `verdict.tier` reading "the
llm-suspected nomination was overruled" is a review note, and withholding the
fingerprint-confirmed copy that carries it is the same drop as reading a `tier` key at any depth.

**Four names, and one reader for all three questions.** The three withheld verdicts, plus
`fingerprint-confirmed`, the one tier a copy finding may be relayed on. The searched-surfaces
refusal, the withhold predicate and the eligibility test all ask that one reader. A caller with
its own, laxer notion of the tier is the defect, twice over: a `{"Tier": "not-found"}` sidecar
passed the schema check unexamined and was then withheld silently, and a
`{"Tier": "fingerprint-confirmed"}` copy was read as a declaration when withholding and as no
declaration at all when relaying, so it was dropped under a count that denied it had declared
anything.

Two limits, both deliberate. **A tier naming none of the four is a tier this producer neither
withheld nor can relay**, and the record takes the ordinary path for its rule id: `## Unparsed`
when nothing maps it, and the not-relay-eligible count when a copy rule does. And **the scope is
the DECLARED tier**: a verdict name spelled in some other field, a `note` or a `summary`, is
opaque payload rather than a verdict, and if nothing else maps the record it goes to
`## Unparsed` verbatim like any other unmappable row. That second limit is safe because of what
the consumer does with the appendix, not merely because of how this producer labels it:
[`review:fanout`](../../../../review/skills/fanout/context/fix-pass-mode.md) surfaces
`## Unparsed` entries to the user for manual handling and cannot auto-classify them, so no
remediation surface acts on a verdict name that reaches the file that way. It does not extend to
a payload cell on a relayed row — an `excerpt` is copied source text and prints as written, which
is why the excerpt belongs to the finding and never carries this run's own reasoning.

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

- Findings to emit → write. The input-refusal gates run first and are the one exception: a
  sidecar that does not parse, one with no `findings` key, one whose `findings` is not a list,
  or one whose `not-found` finding names no searched surfaces is refused whole at exit 3 and
  nothing is written, because a file composed from input that concludes nothing is worse than no
  file. Each refusal names its own cause. A single malformed RECORD is not one of these cases
  and never refuses the sidecar.
- Files scanned, zero relay-eligible findings → write anyway, with the empty `## Findings`
  header. Coverage is the payload, and a clean corpus is a result.
- Nothing scanned (empty target set, everything carved out) → write nothing; say so in the
  report, and name the carve-outs that emptied the set.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After this skill's own `fix` action completes, re-run the audit and emit a
fresh file, so no stale findings file survives its own remediation.
