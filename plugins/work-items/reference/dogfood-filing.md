# Self-observation filing: the shared dogfood contract

When an autonomous lane hits a problem it will **not** fix in the current cycle, such as a bug, a gap,
or a piece of orthogonal drift, it files that problem as a tracker item so the lane's own findings feed
the same queue everyone else works from. That filing rule is **cross-lane-identical**: `work`,
`triage`, `scan-todos`, and the external standing-loop lanes (`source-control:babysit-prs`,
control-tower, enrichment) all file the same way. This document is the single source of truth for
*how*, so each lane references it once instead of restating the rule and letting the copies drift.

The mechanics it composes already live in this plugin: the seam `create-item` verb, the bound
adapter's *Search items* operation, the `track add` body template, and the label taxonomy. This
contract does not re-implement any of them; it **points** at each and adds only the self-observation
policy that binds them into one sequence.

## When it applies: file what you will not fix, nothing else

The default posture is **fix, not file** ([`tracker-seam.md`](tracker-seam.md) "Default = fix, not
file"): a small or medium problem discovered while working is fixed in the current change as its
own commit, even when it is unrelated to the current item. Self-observation filing is the **narrow
exception**. A problem is filed only when it is structural (large enough to need its own planning
pass), urgent and real but unable to land in the current change, or blocked on research this lane
is not positioned to do. No nits, no speculative items.
`work`'s post-green review already draws this line for a deferred review finding ([`../skills/work/SKILL.md`](../skills/work/SKILL.md) "Post-green review
pass"); the same test governs every lane.

## The sequence

Four beats, in order. The two **mechanical** beats reuse existing machinery verbatim; the two
**judgment** beats stay with the model.

1. **Dedupe first (mechanical search + model sameness).** Before creating anything, run the
   search-before-create pre-flight: the bound adapter's *Search items* operation over `--state all`,
   the same read `track add` performs ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
   "Duplicate check"). Whether a hit is *the same problem* is a model judgment, not a string match:
   compare by underlying cause, not wording. A match against an **open** item means comment on it
   instead of opening a second one. A match against a **closed** item is different: closed items are
   absent from the triage attention view, so commenting there buries a still-live or regressed
   observation where no lane will pick it up. Reopen the closed item (or open a fresh active item
   that links it) so the problem re-enters the queue. Where the consuming repo keeps a rejected-concept
   ledger
   (`docs/out-of-scope/`), the same step's ledger check applies. Do not re-file a settled rejection.

2. **Categorize (model judgment).** Classify bug vs enhancement first, since it steers everything
   downstream, then the type and priority, following triage's classification rule
   ([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "Recommend category + state") and the
   label grammar ([`label-taxonomy.md`](label-taxonomy.md)). A self-filed item is raw intake: the
   filer records what it observed, not a verified diagnosis.

3. **File with the fixed shape (mechanical).** File through the canonical `track add` path, which
   owns the body template (Context / Proposed work / Acceptance criteria / References / Metadata) and
   the argv-safe `create-item` write ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
   "Build body", "Create the item"). The shape is not restated here. `track add` is its source of
   truth, so a change to the template lands in one place. The item **title** follows the convention
   in [`issue-conventions.md`](issue-conventions.md).

4. **Label `needs-triage`, then hand off (mechanical label + policy).** Apply `needs-triage` when that exact name exists in the live set ([`label-taxonomy.md`](label-taxonomy.md)). **The filer does not self-triage.** Filing surfaces the problem into raw intake; triage verifies,
   categorizes definitively, and routes it. The org floor workflow applies the same bare label when an issue opens with no `priority:` label (`#506`). Filing still applies it so the item is in the queue on a repository that does not run that workflow.

## Mechanical core is already scripted: reference it, do not duplicate

The "mechanical core" of this contract (dedupe search, filing-template emission, the `create-item`
write) is not a new script to author. It is the existing seam + bound-adapter + `track add`
machinery above. Duplicating it into a standalone wrapper would fork the very template and search
mechanics this document exists to keep single-sourced. The judgment core (sameness, category) is
model work by nature and is not scriptable. A lane composes the two by following the sequence, not by
calling a new binary.

## Autonomous authorization and the AI disclaimer

Model-initiated filing is gated: on the interactive path a lane drafts the item and asks before
creating it ([`../skills/track/actions/add.md`](../skills/track/actions/add.md) "Authorization
gate"). On an **autonomous lane**, a `/loop` or `/schedule` session whose standing rules already
authorize tracker mutations, those standing rules **are** the authorization, the same resolution
triage's direction gate makes ([`../skills/triage/SKILL.md`](../skills/triage/SKILL.md) "Direction
gate"). An autonomous lane prefixes every item and comment it creates with the lane-neutral AI
disclaimer ([`ai-disclaimer.md`](ai-disclaimer.md)), substituting this lane's short name for
`{lane}`.

## Reconciliation note

The authoritative wording of this rule currently also lives in the external v4 standing-loop prompts,
where `source-control:babysit-prs` has not yet absorbed its lane rules (`#477`). This document is the
in-repo surface those prompts and the lane-absorption skills reference; when the remaining absorption
lands, its self-observation wording reconciles against this contract rather than adding a fourth copy.
