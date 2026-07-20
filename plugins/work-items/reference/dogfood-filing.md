# Self-observation filing — the shared dogfood contract

When an autonomous lane hits a problem it will **not** fix in the current cycle — a bug, a gap, a
piece of orthogonal drift — it files that problem as a tracker item so the lane's own findings feed
the same queue everyone else works from. That filing rule is **cross-lane-identical**: `work`,
`triage`, `scan-todos`, and the external standing-loop lanes (`source-control:babysit-prs`,
control-tower, enrichment) all file the same way. This document is the single source of truth for
*how*, so each lane references it once instead of restating the rule and letting the copies drift.

The mechanics it composes already live in this plugin — the seam `create-item` verb, the bound
adapter's *Search items* operation, the `track add` body template, and the label taxonomy. This
contract does not re-implement any of them; it **points** at each and adds only the self-observation
policy that binds them into one sequence.

## When it applies — file what you will not fix, nothing else

The default posture is **fix, not file** ([`tracker-seam.md`](tracker-seam.md) "Default = fix, not
file"): Boy-Scout-scope drift discovered while working belongs in the current change, not the
tracker. Self-observation filing is the **narrow exception** — a problem is filed only when it is
genuinely orthogonal to the current item, large enough to need its own planning pass, or needs
research this lane is not positioned to do. `work`'s post-green review already draws this line for a
VALID-but-deferred finding ([`../skills/work/SKILL.md`](../skills/work/SKILL.md) "Post-green review
pass"); the same test governs every lane.

## The sequence

Four beats, in order. The two **mechanical** beats reuse existing machinery verbatim; the two
**judgment** beats stay with the model.

1. **Dedupe first (mechanical search + model sameness).** Before creating anything, run the
   search-before-create pre-flight — the bound adapter's *Search items* operation over `--state all`,
   the same read `track add` performs ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
   "Duplicate check"). Whether a hit is *the same problem* is a model judgment, not a string match:
   compare by underlying cause, not wording. A match means comment on the existing item instead of
   opening a second one. Where the consuming repo keeps a rejected-concept ledger
   (`docs/out-of-scope/`), the same step's ledger check applies — do not re-file a settled rejection.

2. **Categorize (model judgment).** Classify bug vs enhancement first — it steers everything
   downstream — then the type and priority, following triage's classification rule
   ([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "Recommend category + state") and the
   label grammar ([`label-taxonomy.md`](label-taxonomy.md)). A self-filed item is raw intake: the
   filer records what it observed, not a verified diagnosis.

3. **File with the fixed shape (mechanical).** File through the canonical `track add` path, which
   owns the body template (Context / Proposed work / Acceptance criteria / References / Metadata) and
   the argv-safe `create-item` write ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
   "Build body", "Create the item"). The shape is not restated here — `track add` is its source of
   truth, so a change to the template lands in one place.

4. **Label `needs-triage`, then hand off (mechanical label + policy).** Apply `status:needs-triage`
   ([`label-taxonomy.md`](label-taxonomy.md) status axis) so the item lands in the triage attention
   view for evaluation ([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "Attention view").
   **The filer does not self-triage** — filing surfaces the problem into raw intake; triage verifies,
   categorizes definitively, and routes it. Auto-application of `needs-triage` to a fresh item lacking
   a priority label is tracked separately (`#506`); until it lands, the filing lane applies the label.

## Mechanical core is already scripted — reference it, do not duplicate

The "mechanical core" of this contract (dedupe search, filing-template emission, the `create-item`
write) is not a new script to author — it is the existing seam + bound-adapter + `track add`
machinery above. Duplicating it into a standalone wrapper would fork the very template and search
mechanics this document exists to keep single-sourced. The judgment core (sameness, category) is
model work by nature and is not scriptable. A lane composes the two by following the sequence, not by
calling a new binary.

## Autonomous authorization and the AI disclaimer

Model-initiated filing is gated: on the interactive path a lane drafts the item and asks before
creating it ([`../skills/track/actions/add.md`](../skills/track/actions/add.md) "Authorization
gate"). On an **autonomous lane** — a `/loop` or `/schedule` session whose standing rules already
authorize tracker mutations — those standing rules **are** the authorization, the same resolution
triage's direction gate makes ([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "Direction
gate"). An autonomous lane prefixes every item and comment it creates with the AI disclaimer
([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "AI disclaimer").

## Reconciliation note

The authoritative wording of this rule currently also lives in the external v4 standing-loop prompts,
where `source-control:babysit-prs` has not yet absorbed its lane rules (`#477`). This document is the
in-repo surface those prompts and the lane-absorption skills reference; when the remaining absorption
lands, its self-observation wording reconciles against this contract rather than adding a fourth copy.
