# Interface Design: Design It Twice

The full procedure for the Design-It-Twice branch of the deepening interview. The idea is
Ousterhout's: a designer who draws an interface once tends to keep the first shape that works, and
that shape is seldom the deepest one available. A few deliberately different drafts cost little; a
shallow interface, once callers depend on it, stays for years.

Each section below is written for whoever reads its output: the user reads the framing, each
subagent reads a brief, and the parent reads the returns and decides. The running example is the
tax case from [vocabulary.md](vocabulary.md): the checkout page, the invoice export and the refund
job each look up rates, round and apply exemptions on their own, and the candidate is one deep
`TaxCalculator`.

## 1. The framing the user reads

Before any design exists, the parent writes the framing and shows it to the user. It has three
items:

| Item | What it holds | Tax example |
|---|---|---|
| Constraints | What every proposed interface has to respect: the callers that exist today, the invariants they rely on, and any ordering or speed they already depend on | A refund must round the way its original invoice did; checkout needs its answer within one page request |
| Dependencies | Each dependency with its category from [dependencies.md](dependencies.md) | The rates service another team here runs is `ports-and-adapters`; the exemption list held in memory is `in-process` |
| Sketch | A few lines of code that make the constraints concrete, marked explicitly as **not a proposal**. It illustrates; nobody builds from it | `quote(order)` returning a total, with a comment that refunds pass the original invoice date |

Timing: the framing and the fan-out overlap. The parent posts the framing and dispatches the
subagents in the same turn, and does not hold the dispatch for the user's answer.

## 2. The briefs the subagents read

Launch three or four subagents at once through the Agent tool. Each brief carries one design
constraint, and the constraints are picked to pull against each other, so that following a brief
faithfully cannot lead two subagents to the same shape:

| Constraint | The brief asks for | A shape it might yield for tax |
|---|---|---|
| **Minimal interface** | No more than one to three entry points, each carrying as much behavior as it can | `TaxCalculator.quote(order)` and nothing else |
| **Maximum flexibility** | Room for many kinds of use and for extension later | A rule pipeline the caller assembles: `TaxCalculator.with(rules).quote(order)` |
| **Optimize the common caller** | Find the call site that dominates and make its usual call a single line | `taxFor(cart)` for checkout, plus an options object the refund job fills in |
| **Ports and adapters** | A port declared where the seam sits, with the transport injected. Sent only when the framing classified a dependency as crossing the seam | A `TaxRates` port: the rates-service client in production, `DictTaxRates` in tests |

Besides its constraint, every brief carries the same technical packet. The parent writes it for the
subagent; it is not the framing from section 1 passed along:

| Packet item | Tax example |
|---|---|
| Files and how they are coupled | `checkout/tax.ts`, `export/invoice-tax.ts` and `refunds/recalc.ts`, and which of them share the rounding helper |
| Dependency category | `ports-and-adapters` for the rates service, `in-process` for the exemption list |
| What the seam hides | Rate lookup, rounding and exemption rules |
| Names to use | The [vocabulary.md](vocabulary.md) terms, plus the project's glossary terms when it keeps a glossary; with one name list, the returns can be compared term for term |

## 3. The returns the parent reads

Every subagent answers in six parts, in this order:

| Part | What it holds | What the parent does with it |
|---|---|---|
| 1. **Interface** | All a caller must get right: types, methods, parameters, invariants, call order, failure modes | Measures what a caller has to learn |
| 2. **Usage example** | Code a real caller would write against the design | Checks that the interface reads the way part 1 claims |
| 3. **What the implementation hides** | The complexity kept behind the seam | Measures what the caller gets for part 1 |
| 4. **Dependency strategy** | How each dependency is reached, and which adapters exist | Checks it against the categories in the framing |
| 5. **Trade-offs** | Where the design gives a lot of leverage, and where it gives little | Feeds the comparison |
| 6. **Rejected shapes** | Alternatives the subagent weighed and dropped, each with its `rejected-reason` | Feeds a hybrid |

Part 6 reuses the field name `rejected-reason` from the candidate artifact on purpose, so one
vocabulary covers both.

Part 6 is what lets the recommendation in section 5 graft safely. Without it, a structure chosen
for a reason and a structure that was simply the first to work look the same, and whoever borrows
from the design cannot tell which kind they are taking.

**Part 6 never travels into a fresh-eyes dispatch.** It is authoring rationale, and the delegation
contract hands a reviewer the artifact and not the story. Importing the author's reasoning
re-imports the bias the fresh context exists to remove. It is safe here only because the comparison
in section 4 is done by the parent, which already holds that reasoning. Add an independent judge to
this flow later and part 6 stops at the parent.

## 4. Present and compare

The comparison uses three axes and no others:

| Axis | The question | Tax example |
|---|---|---|
| **Interface depth / leverage** | How much behavior does a caller get per unit of interface it learns? | `quote(order)` hides rates, rounding and exemptions behind one call |
| **Locality of change** | When something changes or breaks, where do the fix, its test and the understanding of it land? | A rounding change stays inside `TaxCalculator`, or also reaches every caller's options object |
| **Seam placement** | Where does the design put its seam, and what does that spot cost or gain? | The `TaxRates` port lets tests run without the rates service, for the price of one more adapter |

Before the comparison, the user sees each design on its own, one at a time, so no design is read
alongside the next one.

### Read what the spread itself tells you

The subagents were pushed apart on purpose, so the shape of their disagreement is evidence.

- **They converged anyway.** Designs that land on the same shape *despite* orthogonal constraints
  pulling them apart is a strong consensus signal, stronger than agreement between candidates given
  the same brief, because this fan-out was built to prevent it. Ship the consensus shape and say why
  the agreement counts.
- **They diverged in shape.** Expected, and evidence of nothing. Orthogonality is the design of this
  step, so shape-divergence is the null result and never a reason to re-frame.
- **They diverged in their assumptions.** Two designs that assume incompatible things about callers,
  invariants, or ordering did not disagree about the answer. They answered different questions.
  That means section 1's framing left those facts open. Re-frame with them pinned and fan out again;
  choosing between the returns would be picking a question, not a design.

## 5. Recommend

The parent's recommendation takes one of three forms, and the comparison decides which:

| Form | Applies when | The parent writes | Tax example |
|---|---|---|---|
| Single winner | One design leads on the axes that matter most for this candidate | The design, and the axis that decided it | Minimal interface: `quote(order)` keeps rounding inside `TaxCalculator`, and a refund fits as a field on the order |
| Hybrid | Two designs each lead on a different axis, and the parts taken from them do not conflict | The hybrid, the part taken from each design, and a graft record (below) | `quote(order)` from minimal interface, with the `TaxRates` port from ports and adapters |
| Withheld | The winner is consequential and research cannot settle it (next paragraph) | The designs side by side, and the evidence that would decide | Whether rates may be cached across a rate change depends on the rates service's published contract |

Every form ends in a named pick or a named missing piece of evidence. A list of options with no
pick is not one of the forms.

**Ground the winner outside the repository too.** When the recommended interface crosses a module, service, or repository boundary, or fixes a published contract, research the pattern it adopts before recommending it: official docs for the platform or library first, then authoritative articles, with recency and dissent noted. State the recommendation's `Basis:`, `verified` with the `file:line`, tool output, or URL, or `judgment` (only when the interface is not consequential: cross-repo, shared infrastructure, irreversible, or security). A consequential winner research cannot settle is withheld: present the designs without a winner and name the evidence that would settle the choice. Contract: [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../../../context/recommendation-basis.md); full convention: [recommendation-basis](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md#grounding-bar).

**A hybrid carries a graft record.** Name what was taken from which design. Then name the part worth
more than the rest: what was considered and left behind, with the reason. A future reader learns most
from the branch that was rejected and why, which is exactly what vanishes when only the winner
survives. A hybrid proposed without one is a shape nobody can later audit. The record lands in the
candidate artifact's `graft-record` field, a sibling of `agreed-shape` rather than part of it. The
Handoff step in [`../../actions/deepening.md`](../../actions/deepening.md) writes it at the same
moment the shape is agreed and `agreed-shape` itself is filled.
