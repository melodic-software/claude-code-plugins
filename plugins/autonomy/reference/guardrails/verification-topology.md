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
| `cross_vendor_checker` | the role a class uses to require vendor disjointness where its own floor does not — under `cross_vendor_required`, every model-adjudicated slot already carries it |
| `ranker` | orders candidates or findings relative to each other rather than scoring one absolutely |

## Checker slots

A class's topology declares a list of checker SLOTS, and a slot is filled by either a DETERMINISTIC
layer or a MODEL-ADJUDICATED role. The distinction is load-bearing: a deterministic layer has no
model or vendor identity, so the relational constraints and predicates below bind only
model-adjudicated slots and are never required of a deterministic one.

**Distinctness is REQUIRED on every slot and cannot be opted out of.** Two slots are distinct only
where they cannot share a failure mode: deterministic slots are distinguished by scanner class,
model-adjudicated slots by resolved model identity. **Two slots that resolve identically declare ONE
checker**, and a binding whose distinct-slot count falls below its class floor is invalid.

A slot NAME tells a validator nothing about what the slot resolves to, so distinctness that is only
intended is not distinctness. **The binding establishes it explicitly**: every model-adjudicated
checker slot declares `distinct_model_from` against the `generator` AND against every other checker
slot in its class. A binding that leaves it undeclared has not established it and is invalid — an
undeclared constraint is the unevaluable case, which is the same failure as declaring none.

Identity equality is the FLOOR of that test, not the whole of it. Two identifiers can name one
underlying model — an alias, a route through a reseller, adjacent versions of one family — and those
share every failure mode while comparing unequal. **A binding declaring two slots it knows resolve
to the same underlying model has declared one checker.** A check cannot see that, so the contract
states the requirement and a check enforces the part it can read; the gap is recorded here rather
than implied away.

The human review the matrix makes mandatory for `C4` is NOT a checker slot. It is the merge gate.

## Relational constraints

A constraint binds a role by its relationship to another role, never by naming an instance.

| Constraint | Resolves via | Why |
|---|---|---|
| `distinct_model_from: <role>` | the model identity the binding declares — static, because a check reads a binding | a model judging its own output measures its own preference, not the artifact |
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

| Class | `min_checkers` | `min_model_checkers` | `cross_vendor_required` |
|---|---|---|---|
| `C1` | 1 | 0 | no |
| `C2` | 1 | 0 | no |
| `C3` | 2 | 1 | no |
| `C4` | 3 | 2 | yes |
| `C5` | 3 | 2 | yes |

`min_checkers` counts DISTINCT slots per the rule above. It is a coverage floor, never a list
length: a class declaring its floor count of slots that resolve identically has declared one
checker, and its binding is invalid.

**`min_model_checkers` exists because a total count cannot express which KIND of coverage is
owed.** Without it, a class meets its floor with deterministic slots alone and never faces a model
judge — and `cross_vendor_required` then binds an empty set and is satisfied by declaring nothing.
So it is never vacuously satisfied: **`cross_vendor_required: yes` requires at least two
model-adjudicated slots, pairwise vendor-disjoint and disjoint from the `generator`**, and a class
asserting it with fewer is invalid rather than trivially conforming.

Each class's composition is absolute, stated against the
[security-review layers](security-review.md) it must not contradict:

- `C1` — one slot: the output-shape check.
- `C2` — one slot: the deterministic scanner layer.
- `C3` — two slots: one deterministic layer and one model judge.
- `C4` and `C5` — three slots: one deterministic layer and two model judges, vendor-disjoint.

Shipped values are FLOORS: a binding may tighten any cell but never weaken one below its shipped
value. The weakening-is-invalid rule is the security-review knobs' own; this leaf adds that no
justification field excuses a weakening either. Floors bind ONLY on the org's security governance
surface, outside the blast radius of the agents they govern; a floor those agents can lower is no
floor. An absent or invalid binding fail-closes to the shipped values above, which this leaf owns —
the matrix cells are their glance restatement.

## Lenses

A slot fixes WHO verifies; a lens fixes what that verifier is asked to look for. Diversity of lens
is the point — two checkers asked the identical question share the blind spot the count exists to
cover, exactly as two slots resolving to one model do.

Lenses bind MODEL-ADJUDICATED slots only. A deterministic slot is not asked a question; its coverage
is fixed by its scanner class, and a lens on it would be decoration.

The vocabulary is CLOSED — a lens the pipeline cannot resolve to a question is a preference, and
preferences are not policy.

| Lens | The question the checker is asked |
|---|---|
| `specification` | does the artifact do what the item asked for |
| `adversarial` | how could it be defeated, abused, or driven to fail |
| `contract` | does it honor the declared interfaces and invariants of everything it touches |
| `regression` | what previously-working behavior does it disturb |
| `evidence` | are the claims made about the artifact supported by artifacts the run actually produced |

**Draw rule.** Distinct model-adjudicated slots draw distinct lenses, in pool order.

**The pool contributes to NO count.** Every floor above is counted over the slots the binding
declares, so no pool value seats a slot, unseats one, or substitutes for one. A pool shorter than a
class's model-adjudicated slot count leaves the remaining slots UNLENSED — judging the artifact
whole, which is what a checker did before this section existed — rather than repeating a lens. An
unrecognized token is recorded as unresolved and draws no lens, on the same footing as the Budget
ceiling: recorded, never enforcing. Angle is the only thing a pool can add, and the only thing it
can fail to add.

The pool therefore binds in plugin `userConfig`, not on the security binding: nothing it can be set
to changes how many slots a class runs, how they must differ, or whether one must be cross-vendor.

## Where each axis binds

Two homes, and the difference is not convenience. An axis fixing HOW MUCH verification a class gets
binds on the org's security governance surface, outside the blast radius of the agents it governs.
An axis fixing WHAT ANGLE that verification takes binds on the operator's own plugin-option surface,
which resolves from user-scope, invocation-scope, and managed settings only — a watched
repository's in-tree settings are not read for plugin options, so a repo an agent can write cannot
dial its own verification.

| Axis | Home |
|---|---|
| `min_checkers`, `min_model_checkers`, `cross_vendor_required` | security binding |
| slot distinctness, relational constraints, predicates | security binding, inside the class's declared slots |
| the lens pool | plugin `userConfig` |
| whether the advisory narration lane runs | plugin `userConfig` |

**Raise, never lower.** The asymmetry is the whole reason the split exists. Tightening a binding
cell is legal; weakening one is invalid per the floor rule above. `userConfig` reaches no floor at
all and cannot be made to: the pool contributes to no count, and the narration lane has no cell to
weaken. A degenerate pool costs angle, never coverage — the slots still run, still resolve
distinctly, and still owe unanimity. The reachable outcomes are a lensed checker or an unlensed one,
never fewer checkers than the class's floor.

## The advisory narration lane

An OPTIONAL lane that reads a difference a deterministic layer has ALREADY detected and writes a
plain-language account of it into the run record. Advisory only: it emits no verdict, fills no
checker slot, is counted by no floor, and never gates a transition. Its output reaches the human
gate as narration attached to the deterministic finding it explains.

**Its position is upstream-dependent, not configurable.** It never runs first, and never runs on an
artifact no deterministic layer flagged. A lane with nothing upstream of it has nothing to narrate
and produces nothing.

**It carries no authority cell, by construction rather than by default.** The table above gives it
no cell on the security binding, its schema carries none, and `userConfig` carries only whether it
runs. Nothing an org could flip promotes it — a stronger property than a knob shipped off.

**What this does NOT rule out, stated plainly.** A class may declare a model-adjudicated checker
SLOT whose `requires_modality` names an image input, and a security-review layer may gate on that
slot. That slot is a CHECKER: counted by the floors, held distinct, bound by every relational
constraint, and owing unanimity. It is a different governance object from this lane, which is
counted by nothing and owes nothing. The measurements below bear on both, and a class declaring such
a slot should read them — but only the lane is structurally incapable of gating.

**Why the lane is shaped this way — measured, not assumed.** Model judgment over rendered UI
artifacts tops out below the precision a gate needs, and its characteristic error is declaring
broken things fine: the wrong direction for a check whose purpose is catching breakage. Its verdict
on identical input also varies run to run at a rate well above the level at which a suite stops
being believed, and that variance is a property of hosted inference the operator cannot tune away —
no temperature setting or seed removes it. Recall is where it is strong, which is precisely what
makes narration its job rather than judgment. Every established comparison product surveyed reaches
the same arrangement independently: detect the difference deterministically, narrate it with a
model, route acceptance to a person. Per-request image caps and per-frame metering make a lane's
artifact volume a cost bound the runner resolves against the bound instance's declared limits, never
a policy axis. The sourced measurements live in the pull request that introduced this lane and on
the issue it closes, deliberately outside the contract surface.

**Not demonstrated at runtime.** With no runner built there is no runtime in which to exercise the
ordering, so the property claimed here is structural: no cell exists through which authority could
be granted. The runtime assertion — that a deterministic pass carrying a narration finding still
advances — is a DEFERRED item bound to the runner's build trigger, not a claim made here.

## Two fixed invariants

Neither is a knob, and no binding may relax either.

**Independent aggregation, never deliberation.** Checkers run isolated: no checker sees another
checker's verdict or reasoning, and verdicts are combined mechanically. Deliberation between
checkers is RECORDED AS REJECTED: agreement reached by discussion is correlation, not corroboration
— the count of agreeing checkers stops measuring independent confirmation the moment they can hear
each other, so a deliberating panel's unanimity means strictly less than an isolated panel's while
reading as if it meant more.

**Unanimous checker agreement for anything auto-proceeding.** Every transition a run takes without a
human — not merge alone — requires every checker the class declares to agree. One dissent withholds
the automatic transition and hands the item to the human gate; divergence routing is owned by the
matrix's escalation contract.

## How unanimity is enforced today

Unanimity needs a checker POPULATION and FORCE behind its verdicts. This leaf's floors supply the
population; the [security-review leaf](security-review.md)'s per-class blocking knob supplies the
force. Only force is configurable into absence — floors are tighten-only, so no floor value can
describe a topology that cannot be unanimous, while a knob left below `blocking` lets a dissent be
recorded and the transition proceed anyway.

**Binding-validity rule.** A class whose merge disposition is bound `auto` is INVALID, rejected at
check time, when either holds:

- any verification layer for that class is bound `advisory` — the checker runs, dissents, and the
  transition proceeds regardless; or
- the class declares a model-adjudicated checker slot while its model-adjudicated layer is bound
  `not-required` — the layer that slot judges in never runs, so its agreement can never be obtained
  and unanimity over it is vacuous.

A class declaring no model-adjudicated slot is not caught by the second case: its floor is seated by
a deterministic slot, whose force is its own layer. The rule is a JOIN across two axes, never a floor
on either — each axis alone at a legal value can still combine into an automatic transition no
checker can withhold.

**Dissent routes on the existing channel.** A withheld transition files on the bound route for the
matrix's `verification-divergence` event class, whose definition already covers checker
disagreement. No token and no channel is added here; the one-channel invariant binds unchanged.

**Consumers resolve both.** A consumer resolving a class's merge disposition must resolve its
checker layers in the same step, against live promotion-evidence telemetry: automatic merge is
unavailable whenever a checker layer resolves below `blocking`, including where a human-ratified
`blocking` has been lowered by automatic demotion. Reading the bound merge disposition alone is
non-conforming.

**Why the check is merge-scoped while the obligation is not.** The obligation covers every
transition a run takes without a human. Merge is the only such transition a binding can express:
intermediate pipeline transitions are runner-owned, and no runner exists. Autonomous ADMISSION is
not a second hole — admission precedes the artifact, so there is no checker verdict to be unanimous
about at that point.

**Two limits, stated rather than hidden.** Neither is verified anywhere today.

- **Per-run aggregation is not asserted.** Unanimous pass, single dissent, checker timeout, and
  duplicate checker identity at run time are verdict-aggregation obligations on the runner seam,
  deferred to the runner's build trigger. What ships is the contract obligation and the
  binding-validity rule above: a configuration that could auto-proceed with no force behind its
  checkers is rejected; a RUN that does so is not yet detectable.
- **Force is checked; RESOLVED distinctness is not.** The slot rule above is stated over the binding
  because a binding is what a check can read. Two slots held distinct by declared constraints can
  still resolve to one instance at run time, and no static check sees that — it is the same
  runner-seam obligation.
