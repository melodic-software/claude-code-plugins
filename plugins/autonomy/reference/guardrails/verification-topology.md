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
| `cross_vendor_checker` | a `checker` additionally constrained to a different vendor from the `generator` |
| `ranker` | orders candidates or findings relative to each other rather than scoring one absolutely |

## Relational constraints

A constraint binds a role by its relationship to another role, never by naming an instance.

| Constraint | Resolves via | Why |
|---|---|---|
| `distinct_model_from: <role>` | model identity at run time | a model judging its own output measures its own preference, not the artifact |
| `distinct_vendor_from: <role>` | vendor identity | disjoint model families fail independently; same-vendor checkers share failure modes, so agreement between them is weaker evidence than its count suggests |
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
against an org-maintained table; a price that will not resolve leaves the role UNPROVEN and the
class's topology invalid, per the contract's uniform fail-closed rule.

## Pins

`pinned_model_id` is the one place a concrete instance identifier is legal, and only to reproduce a
RECORDED MEASUREMENT. Append-only: a recorded result keeps its pin forever, so pins accumulate and
never need updating. A pin never selects a role for new work and is never a policy default.

## Rejected vocabulary: capability labels

Capability labels — words naming how capable a model is, rather than what it must do or how it must
differ — are RECORDED AS REJECTED as policy vocabulary. Falsified twice over: each such word names a
different thing at each vendor, and none survives a model release. No such label appears anywhere in
this contract; a binding that introduces one is expressing preference where the contract requires a
resolvable constraint. The sourced per-label evidence lives in the change record that introduced
this leaf, deliberately outside the contract surface.

## Shipped floors

| Class | `min_checkers` | `cross_vendor_required` |
|---|---|---|
| `C1` | 1 | no |
| `C2` | 1 | no |
| `C3` | 2 | no |
| `C4` | 3 | yes |
| `C5` | 3 | yes |

**`min_checkers` counts DISTINCT checker roles, each satisfying its own relational constraints —
never repeated runs of one instance.** N runs of a single instance count as one checker: they share
the failure the count exists to catch.

Shipped values are FLOORS: a binding may tighten any cell but never weaken one below its shipped
value, and no justification field excuses a weakening — the same rule the security-review knobs
carry. Floors bind ONLY on the org's security governance surface, outside the blast radius of the
agents they govern; a floor those agents can lower is no floor. An absent or invalid binding
fail-closes to the shipped values above.

## Two fixed invariants

Neither is a knob, and no binding may relax either.

**Independent aggregation, never deliberation.** Checkers run isolated: no checker sees another
checker's verdict or reasoning, and verdicts are combined mechanically. Deliberation between
checkers is RECORDED AS REJECTED — falsified: a measured deliberative protocol scored BELOW every
single-model baseline it was built from, while independent aggregation over the same models scored
above them. Agreement reached by discussion is correlation, not corroboration.

**Unanimous checker agreement for anything auto-proceeding.** Every transition a run takes without a
human — not merge alone — requires every checker the class declares to agree. One dissent withholds
the automatic transition and hands the item to the human gate; divergence routing is owned by the
matrix's escalation contract.
