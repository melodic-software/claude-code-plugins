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
