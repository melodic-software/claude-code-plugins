# Scan Briefing: canonical subagent prompt for Phase 1

The friction scan fans out read-only exploration subagents. Brief every scan subagent with the
structure below, the same way [interface-design.md](interface-design.md) briefs the Design-It-Twice
agents. A canonical briefing keeps scan quality from varying run-to-run and puts the
badge-acceptance heuristics in front of each agent while it is still forming its confidence rating.

Assemble one briefing per subagent. Each briefing has five parts: vocabulary primer, friction
checklist, dependency categories, badge-acceptance heuristics, and the per-candidate return schema
with its stopping point. The examples below use the tax case from [vocabulary.md](vocabulary.md);
a real briefing names the agent's own area instead.

## 1. Vocabulary primer

The agent names what it finds with the eight terms defined in [vocabulary.md](vocabulary.md), in
that file's order: **module, interface, implementation, seam, adapter, depth, leverage, locality**.
The same file lists the words the agent must not use in their place (*component*, *service*,
*boundary*) and the reading of depth it must not adopt (a count of implementation lines against
interface lines). Add the project's own glossary terms when the project keeps a glossary. A report
built from agents that each picked their own words cannot be compared candidate to candidate.

## 2. Friction checklist

The agent stays inside its assigned area and records every place one of these signals appears.
They are the Phase 1 signals of [../../actions/deepening.md](../../actions/deepening.md), restated
for a subagent:

| Signal | What the agent sees | Tax example |
|---|---|---|
| Untested **interface** | Code with no tests, or code whose current interface makes a test awkward to write | A test of one rate has to stub three collaborators of `TaxCalculator` |
| **Shallow** module | A caller has to learn about as much as the implementation contains | `TaxRateLookup.get(region)` does nothing but forward to the rates client |
| Scattered concept | Following one idea means opening one small module after another | Rounding is split across `roundHalfEven`, a `RoundingPolicy` class and a helper in each caller |
| Missing **locality** | Pure functions were pulled out to be easy to test, while the defects sit in the code that calls them | `applyExemption()` is fully covered, and the refund job passes it the wrong date |
| Leaking **seam** | Two modules are coupled so tightly that the details of one show up across the other's seam | The invoice export reads the rates client's cache keys |
| Defects between subsystems | The same kind of defect keeps appearing where several owned subsystems meet, not inside any one of them | Checkout and the refund job disagree on a total by one cent |

Three further signals belong to this scan alone; record them in the same way:

| Signal | What the agent sees | Tax example |
|---|---|---|
| State held too broadly | A value lives where far more code can reach it than reads it, or a derived value is saved and refreshed on each change when it could be worked out at the moment it is read. Rank the possible homes from broadest to tightest (globals, module state, an object's fields, locals, function parameters) and flag state kept higher than its readers require | `invoice.taxTotal` is written back after each line edit rather than added up on read; checkout assigns a module-level `currentRegion` and then calls `quote()` |
| Hops that add little | Answering one question about a request walks the reader through a chain of files or layers, each contributing little beyond passing the call on. How long is too long depends on how deep this codebase's other paths run; there is no threshold number | Tax for one line passes the controller, then `TaxService`, `TaxFacade` and `TaxRateLookup`, before it reaches the rates client |
| One caller's rule in shared code | Code every caller uses carries a branch that serves a single caller, and each caller added later carries it too. Leave the shared work where it is and hand that one decision back to the caller that wants it | `TaxCalculator.quote()` picks a date only after asking whether the refund job is calling; the refund job could supply its own date |

Four more signals are hazards that mislead an agent editing the code. Judge each by the
**open-file test**: with only the file being edited open, can an agent see every other place it
must change? A "no" confirms the hazard, and the candidate cites the test in `shallow-signal`.

| Signal | What the agent sees | Tax example |
|---|---|---|
| Split ownership | More than one module writes the same state or keeps its own copy, so an agent that edits one writer cannot see the others. Remedy: one owner per piece of state; the others read it or ask the owner | Checkout and the refund job both write `order.taxRegion`, and the invoice export keeps its own copy |
| Two ways to do one task | An agent copies whichever way it finds first, so every way keeps gaining callers. Remedy: keep one way; move callers off the others and delete them in the same change | Rounding is done by `roundHalfEven` in one caller and by `RoundingPolicy` in another, and each gains callers |
| Importable internals | An agent takes the shortest path that compiles and imports internals directly, which makes them part of the interface. Remedy: make internals unreachable from outside, so such an import fails the build | The invoice export imports `RatesCache` from inside the rates client's package |
| Hand-synced list | Two or more places list the same items and adding one means editing every list; an agent updates only the list it sees. Remedy: keep one list and derive the others, or fail the build when they disagree | Supported regions are listed in the rate table, the validator and the region picker |

Run the **deletion test** on anything that looks shallow, and record the result in the schema's
`deletion-verdict` field: `concentrates` is the candidate signal and `moves` marks a pass-through,
with both results defined in [vocabulary.md](vocabulary.md) and Phase 1.

When judging whether an area is tested, a suite that skips because a required tool is missing is
not a pass, and a stub standing in for the tool is not the tool. Report such an area as unverified,
never as covered.

## 3. Dependency categories

Each of a candidate's dependencies gets one of the four labels defined in
[dependencies.md](dependencies.md), written in the schema's `category` field exactly as that file
spells it. The label matters because it fixes which testing strategy the eventual recommendation
can name. In the tax case, the rates service run by another team here is `ports-and-adapters`, and
a third-party geocoding provider would be `mock`.

## 4. Badge-acceptance heuristics (calibrate confidence at scan time)

Have the agent rate its own confidence **against the two acceptance heuristics**, not on gut feel.
Calibrating at scan time is what lets Phase 1.5 verify against a stated bar rather than a hunch.

- **Deletion test (acceptance form)**: would a future maintainer, finding this module gone, rebuild
  it substantially the same way? If not, the boundary is arbitrary and the candidate is weak.
- **Two-adapter rule**: an abstraction or port earns its existence only with two real
  consumers/adapters (typically production + test). A candidate whose value hinges on a one-adapter
  abstraction is speculative indirection, and earns `speculative` confidence at best.

One more piece of evidence comes from tracing the value a candidate revolves around. In the tax
case, `TaxRateLookup` supplies the rate an order is charged, yet listing everything able to alter
that rate takes the rates client, its cache and a nightly refresh job. The agent runs the same two
traces on its own candidate, writers first and then the source: every piece of code permitted to
modify the value, and the place the value is first made. A trace that spans several modules goes
into `shallow-signal`. Neither trace is a third heuristic; both feed the rating, and the two
heuristics above still settle it.

## 5. Per-candidate return schema

Every agent returns each candidate in this exact shape, so Phase 1.5 can verify and Phase 2 can
render without re-deriving structure:

```markdown
- title: <short candidate name>
- files: <comma-separated paths>
- problem: <one sentence naming the friction, in vocabulary terms>
- shallow-signal: <the concrete observation that is the evidence for shallowness, e.g. "three one-method
  wrappers each forwarding their argument"; this is what Phase 1.5 reproduces>
- category: in-process | local-substitutable | ports-and-adapters | mock
- deletion-verdict: concentrates | moves
- test-surface: <what a test at the deepened interface would assert>
- confidence: strong | worth-exploring | speculative   # calibrated against §4, not gut feel
- runtime-claim: <only if the candidate asserts a live bug or dead code. State it explicitly so
  Phase 1.5 knows to reproduce it; omit otherwise>
```

The `shallow-signal` and `runtime-claim` fields exist specifically so the verification gate
(Phase 1.5) has something concrete to reproduce rather than a bare assertion.

End every briefing with its stopping point: the agent is done when it has walked the friction
checklist over its assigned area and returned every candidate in this schema, or said it found
none; it returns early with what it has when a candidate needs code outside that area.
