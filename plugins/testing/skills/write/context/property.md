# Write Property Tests

A property test states something that must hold for every valid input and lets a generator search
for an input that breaks it. Use it alongside example tests, not instead of them: the TDD cadence
in [write.md](write.md) still applies, and each property is one slice.

## When a property beats examples

Reach for a property when the input space is large and a rule over it is easier to state than a
list of cases:

- **Parsers and serializers**: any valid input parses without error; a formatted value parses back
  to the same value.
- **Pure transforms**: sorting, normalizing, filtering, pricing rules, encoders, where an output
  relation holds for all inputs.
- **Collections and stateful classes**: a class whose methods mutate it (`push`/`pop`,
  `add`/`remove`, `open`/`close`). Its bugs depend on call order, which no single-call example
  reaches; a stateful property runs generated call sequences.

Keep example tests for the cases a reader needs to see spelled out (the documented edge cases, the
bug that was reported), and for logic with few inputs, where a property adds nothing a table of
cases does not.

## State the property before reading the code

Write each property from stated intent: the spec, the acceptance criteria, the issue, the
docstring, the type, the way callers use the code. Do that before reading the implementation. A
property read off the implementation restates it, the same defect `testing:test-value` §1 forbids
for expected values, and it passes when the code is wrong. LLM-written properties are often
unsound (the property does not actually hold) or superficial (a wrong implementation also
satisfies it). That was measured on LLM property generators over Python libraries and benchmark
functions, and the transfer to an agent writing properties for its own code is inferred.

## Patterns

Two patterns have independent backing across several publishers; prefer them:

- **Oracle or model-based.** Compare the code against a reference implementation or a simpler
  model: an optimized function against a slow obvious one, a stateful class against a plain list or
  dict driven by the same generated operations. Keep the model simple. A model that reimplements
  the logic under test agrees with the code even when the code is wrong.
- **Metamorphic.** Relate outputs for related inputs when no single output is known:
  `search(q)` results contain `search(q + " extra")` results for a narrowing filter, `sin(pi - x)`
  equals `sin(x)`, adding an unrelated record does not change a total.

Two more are common but have thinner independent backing (MEDIUM in the research), so use them as
one check among others, not as the only oracle:

- **Round trip**: `decode(encode(x)) == x`. Passes when both directions share a mistake, so pair it
  with a known encoded fixture, as the per-cycle checklist in [write.md](write.md) says.
- **Algebraic invariants**: idempotence (`f(f(x)) == f(x)`), commutativity, an output size bound
  (`len(filter(xs)) <= len(xs)`).

## Generators

Leave generators unconstrained unless the code's contract requires a constraint: an unbounded list
strategy, not one capped at 100 items "to be safe". Every constraint is a region the search never
visits. Generate only inputs the code can legitimately receive (sound), and as many of those as is
practical (complete); a sound, mostly complete generator beats an elaborate one.

## A failing property

1. **Triage first.** A new property's failure is either a real bug or a wrong property (an input
   the code is documented never to receive, a rule that was misread). Re-read the stated intent
   before changing code or the property. Never weaken the property just to make it pass.
2. **Pin the shrunk counterexample.** Once a bug is confirmed, check the minimal failing input in
   as an explicit example on the property (Hypothesis `@example`, fast-check `examples`), so the
   regression runs on every run before generation. A seed, a path or the tool's example database
   is a replay handle for reproducing the failure now, not the durable regression: Hypothesis
   documents its database as a cache, and seeds are not guaranteed to survive a tool upgrade
   (shown for Hypothesis and QuickCheck; unchecked for the others, so treat this as guidance).
3. **Then fix**, and keep the explicit example after the fix.

Mechanics live in each tool's docs: Hypothesis
[`@example` and `example.xfail()`](https://hypothesis.readthedocs.io/en/latest/reference/api.html)
and [replaying failures](https://hypothesis.readthedocs.io/en/latest/tutorial/replaying-failures.html);
fast-check [`examples`, `seed` and `path`](https://fast-check.dev/docs/configuration/user-definable-values/).
As of 2026-10-06. Recheck trigger: a tool stops recommending explicit examples over its database
or seed, or renames these parameters.

## Show the property can fail

A property that has never failed is unproven. Before relying on one, give it evidence: run
`/mutation-testing:audit --exercised <test-path>` (when the `mutation-testing` plugin is enabled)
and confirm the property kills mutants in the code it covers, or add a known-bad input the property
must reject as an expected-fail example (Hypothesis `@example(...).xfail()`). A property that
kills no mutant and trips on no bad input is a weak oracle; tighten it or replace it with
examples.

## Python: the Hypothesis team's command

For Python, the Hypothesis maintainers publish a `/hypothesis` Claude Code command that encodes
this loop (evidence-backed properties, failure triage, pinning the minimal input). Use it rather
than re-deriving it here:
[`.claude/commands/hypothesis.md`](https://github.com/HypothesisWorks/hypothesis/blob/master/.claude/commands/hypothesis.md).
As of 2026-10-06 (announced 2025-11-01). Recheck trigger: the file moves, is retired, or ships as a
plugin.

Basis: the agent-self-check research slice (2026-10-06), prompted by Addy Osmani's 2026-10-05 post
(<https://x.com/addyosmani/status/2106995301802541481>). Agentic property testing found real bugs
in mature Python libraries (one workshop paper, NeurIPS 2025), alongside the unsound-property rate
above. Recheck trigger: a measurement of agents writing properties for their own code under
development.
