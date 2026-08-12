# Verification topology

Normative leaf of the [guardrail contract](../guardrails.md): WHO verifies a change, how those
verifiers must differ from each other, and the per-class floor for how many there are. The
[security-review leaf](security-review.md) owns which verification LAYERS exist and which of them
gate a merge; this leaf owns the population that runs them. Roles, constraints, and predicates are
contract vocabulary; every concrete model instance is an org-binding outcome on the binding seam.

## Roles

Roles are properties of THIS pipeline, not of any vendor's roster, so a roster change never edits
policy — only the binding that resolves a role to an instance.

| Role | Adjudicates |
|---|---|
| `generator` | produces the artifact under verification |
| `checker` | judges that artifact, in isolation from every other checker |
| `cross_vendor_checker` | a `checker` additionally constrained to a vendor shared with no other checker and not the `generator`'s |
| `ranker` | orders candidates or findings relative to each other rather than scoring one absolutely |

## Checker slots

A class's topology declares a list of checker SLOTS, and a slot is filled by either a DETERMINISTIC
layer or a MODEL-ADJUDICATED role. The distinction is load-bearing: a deterministic layer has no
model or vendor identity, so the relational constraints and predicates below bind only
model-adjudicated slots and are never required of a deterministic one.

**Distinctness is implied on every slot — it is not something a binding opts into.** Two slots are
distinct only where they cannot share a failure mode: deterministic slots are distinguished by
scanner class, model-adjudicated slots by resolved model identity. **Two slots that resolve
identically declare ONE checker**, and a binding whose distinct-slot count falls below its class
floor is invalid. The rule is stated over the BINDING rather than over runs, because a binding is
what a check can read.

The human review the matrix makes mandatory for `C4` is NOT a checker slot. It is the merge gate.

## Relational constraints

A constraint binds a role by its relationship to another role, never by naming an instance.

| Constraint | Resolves via | Why |
|---|---|---|
| `distinct_model_from: <role>` | model identity at run time | a model judging its own output measures its own preference, not the artifact |
| `distinct_vendor_from: <role>` | vendor identity | disjoint model families fail independently; same-vendor checkers share failure modes, so agreement between them is weaker evidence than its count suggests. `cross_vendor_required` therefore obliges vendor disjointness AMONG the model-adjudicated slots as well as from the `generator` — a class whose checkers all share one vendor satisfies neither the constraint nor the reason for it |
| `not_weaker_than: <role>` | an ordering source the binding declares | PRESENT BUT NOT DEFAULTED — no cross-vendor capability ordering exists to evaluate it against, so no shipped default uses it. A binding may state it only where it also declares its own ordering source |

A constraint naming a role that its own class does not declare is invalid, not ignored.

## Machine-checkable predicates

A predicate is a requirement a binding can EVALUATE against a candidate instance. A requirement that
cannot be evaluated is a preference, and preferences are not policy.

| Predicate | Resolution source |
|---|---|
| `min_context_tokens: N` | the declared input limit of the bound instance |
| `requires_modality: [...]` | the declared input/output modalities of the bound instance |
| `requires_feature: [...]` | the bound instance's declared feature set — feature NAMES are vendor-local, so the binding declares the mapping it resolves against |

## Budget

`max_input_cost_per_mtok` / `max_output_cost_per_mtok` — a per-role ceiling. This REFINES the
matrix's cost-tier column and never replaces it: the tier is the class-level cost vocabulary, the
ceiling is a numeric bound inside it. No vendor supplies a price feed, so the ceiling resolves
against an org-maintained table.

**The ceiling is RECORDED, never enforcing.** A price that will not resolve is recorded as
unresolved; it does not invalidate a binding and does not gate a run. The matrix states that cost
enforcement is out of scope, and hard spend caps are gated behind their own trigger — a ceiling that
blocked here would quietly make this leaf the one enforcing exception to both.

## Pins

`pinned_model_id` is the one place a concrete instance identifier is legal, and only to reproduce a
RECORDED MEASUREMENT. Append-only: a recorded result keeps its pin forever, so pins accumulate and
never need updating. A pin never selects a role for new work and is never a policy default.

## Rejected vocabulary: capability labels

Capability labels — words naming how capable a model is, rather than what it must do or how it must
differ — are RECORDED AS REJECTED as policy vocabulary. Falsified twice over: each such word names a
different thing at each vendor, and none survives a model release. No such label appears anywhere in
this contract; a binding that introduces one is expressing preference where the contract requires a
resolvable constraint. The sourced per-label evidence lives in the pull request that introduced this
leaf and on the issue it closes, deliberately outside the contract surface.

## Shipped floors

| Class | `min_checkers` | `cross_vendor_required` |
|---|---|---|
| `C1` | 1 | no |
| `C2` | 1 | no |
| `C3` | 2 | no |
| `C4` | 3 | yes |
| `C5` | 3 | yes |

`min_checkers` counts DISTINCT slots per the rule above. It is a coverage floor, never a list
length: a class declaring its floor count of slots that resolve identically has declared one
checker, and its binding is invalid.

The floors compose with the [security-review layers](security-review.md) rather than duplicating
them — `C1`'s single slot is its output-shape check and `C2`'s is the deterministic scanner layer,
so neither class is obliged a model judge its verification cell does not require; `C3` adds one
model-adjudicated slot; `C4` and `C5` add two, vendor-disjoint.

Shipped values are FLOORS: a binding may tighten any cell but never weaken one below its shipped
value. The weakening-is-invalid rule is the security-review knobs' own; this leaf adds that no
justification field excuses a weakening either. Floors bind ONLY on the org's security governance
surface, outside the blast radius of the agents they govern; a floor those agents can lower is no
floor. An absent or invalid binding fail-closes to the shipped values above, which this leaf owns —
the matrix cells are their glance restatement.

## Two fixed invariants

Neither is a knob, and no binding may relax either.

**Independent aggregation, never deliberation.** Checkers run isolated: no checker sees another
checker's verdict or reasoning, and verdicts are combined mechanically. Deliberation between
checkers is RECORDED AS REJECTED — falsified: agreement reached by discussion is correlation, not
corroboration, so a deliberating panel converges toward whichever verdict is stated most
persuasively rather than toward the one the artifact supports, and the count of agreeing checkers
stops measuring independent confirmation the moment they can hear each other.

**Unanimous checker agreement for anything auto-proceeding.** Every transition a run takes without a
human — not merge alone — requires every checker the class declares to agree. One dissent withholds
the automatic transition and hands the item to the human gate; divergence routing is owned by the
matrix's escalation contract.
