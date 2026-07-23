# Scan Briefing — canonical subagent prompt for Phase 1

The friction scan fans out read-only exploration subagents. Brief every scan subagent with the
structure below, the same way [interface-design.md](interface-design.md) briefs the Design-It-Twice
agents — so scan quality does not vary run-to-run and the badge-acceptance heuristics reach the
agents at scan time instead of arriving only in Phase 2.

Assemble one briefing per subagent. Each briefing has four parts: vocabulary primer, friction
checklist, dependency categories, and the per-candidate return schema. Include the project's own
glossary terms (if it maintains one) alongside the architecture vocabulary so every agent names
things the same way.

## 1. Vocabulary primer

Give each agent the deepening terms it must use — **module, interface, implementation, depth, seam,
adapter, leverage, locality** — from [vocabulary.md](vocabulary.md), and the rejected framings
(never *component*, *service*, *boundary*, or depth-as-line-ratio). Consistent language is the
point: a report assembled from agents that each named things differently is not comparable.

## 2. Friction checklist

The agent walks its assigned area of the codebase and notes where friction appears, against the same
questions Phase 1 asks:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as implementation?
- Where have pure functions been extracted for testability, but real bugs hide in how they're
  called (no **locality**)?
- Where do tightly-coupled modules leak across their **seams**?
- Where do bugs recur *at the seams between* several owned subsystems rather than inside any one?
- Which parts are untested, or hard to test through their current **interface**?

Apply the **deletion test** to anything suspected shallow: would deleting it *concentrate*
complexity (the signal — earning its keep) or merely *move* it (a pass-through)?

## 3. Dependency categories

The agent classifies each candidate's dependencies per [dependencies.md](dependencies.md) —
in-process, local-substitutable, ports-and-adapters (remote-but-owned), or mock (true external) —
because the category determines the testing strategy the eventual recommendation names.

## 4. Badge-acceptance heuristics (calibrate confidence at scan time)

Have the agent rate its own confidence **against the two acceptance heuristics**, not on gut feel —
this is what F4 fixes: heuristics applied at scan time instead of arriving only in Phase 2.

- **Deletion test (acceptance form)** — would a future maintainer, finding this module gone, rebuild
  it substantially the same way? If not, the boundary is arbitrary and the candidate is weak.
- **Two-adapter rule** — an abstraction or port earns its existence only with two real
  consumers/adapters (typically production + test). A candidate whose value hinges on a one-adapter
  abstraction is speculative indirection — `speculative` confidence at best.

## 5. Per-candidate return schema

Every agent returns each candidate in this exact shape, so Phase 1.5 can verify and Phase 2 can
render without re-deriving structure:

```markdown
- title: <short candidate name>
- files: <comma-separated paths>
- problem: <one sentence — the friction, in vocabulary terms>
- shallow-signal: <the concrete observation — the evidence for shallowness, e.g. "three one-method
  wrappers each forwarding their argument"; this is what Phase 1.5 reproduces>
- category: in-process | local-substitutable | ports-and-adapters | mock
- deletion-verdict: concentrates | moves
- test-surface: <what a test at the deepened interface would assert>
- confidence: strong | worth-exploring | speculative   # calibrated against §4, not gut feel
- runtime-claim: <only if the candidate asserts a live bug or dead code — state it explicitly so
  Phase 1.5 knows to reproduce it; omit otherwise>
```

The `shallow-signal` and `runtime-claim` fields exist specifically so the verification gate
(Phase 1.5) has something concrete to reproduce rather than a bare assertion.
