# Property-Based Testing

What a property is, why shrinking matters, which property shapes are well documented, how
properties sit beside example tests, and what the 2024-2026 evidence says about properties an
agent writes.

**Provenance, read first.** Neither Beck nor Khorikov covers property-based testing, and this file
is **not** a book distillation. It was built from web sources read on 2026-10-06: tool
documentation, two papers' abstract and HTML pages, and one conference page. No property-based
testing book was read. Every claim below carries the confidence the research gave it; the sources,
their read depth, and the recheck trigger are in [Sources](#sources) at the end.

## A Property Specifies What Must Never Happen

An example test pins one input to one expected output. A property states something that must hold
for **every** input in a class, or, read the other way, what must never happen for any of them:
decoding an encoded value never yields a different value; a sorted list is never out of order and
never loses an element; the system never disagrees with a simpler model of it. The tool then
generates many inputs and searches for one that breaks the statement.

That makes a property a specification, so it has to come from stated intent: a requirement, the
API docs, a docstring, an issue. Current agent property tooling and research all draw properties
from intent rather than from the implementation's observed behavior (HIGH: Kiro's correctness
docs, the Hypothesis team's `/hypothesis` command, Vikram et al.). None of the three hides the code
from the property author, so "never read the code" is not what they show; "derive the property from
what the code claims to do" is.

**Editorial synthesis, outside Beck and Khorikov.** A property that re-derives its expectation from
the implementation (`add(a, b) == a + b` for an `add` that is `a + b`) is the tautology Khorikov
calls leaking domain knowledge into tests
([anti-patterns-khorikov.md, section 3](anti-patterns-khorikov.md#3-leaking-domain-knowledge-to-tests)).
Generating many inputs does not repair it: every input passes for the same reason.

## Shrinking: the Failure Arrives Minimal

When a generated input breaks a property, the tool shrinks it: it searches for a smaller input that
still fails and reports that one. The documentation of Hypothesis, fast-check, rapid, CsCheck,
FsCheck and QuickCheck each states both shrinking and a way to replay the failure (HIGH; these are
documentation statements, not a live probe of each tool).

The durable regression is the **minimal failing input checked in as an explicit example**, not the
replay handle. Hypothesis documents its example database as a cache that may be invalidated and
recommends an explicit `@example` instead; fast-check offers an `examples` parameter for the same
purpose (both HIGH, single source each). Whether seeds and replay blobs break across library
versions in general is open: it is documented for Hypothesis and QuickCheck only (MEDIUM), so
"prefer the input over the seed" is guidance, not an established cross-tool fact.

## Patterns, by Strength of Evidence

| Pattern | What the property compares | Confidence |
|---|---|---|
| Oracle or model-based | The system against a reference implementation or a simpler model, including stateful command sequences run against both | HIGH |
| Metamorphic | Outputs for related inputs (doubling an input doubles a total; filtering twice equals filtering once by the conjunction) | HIGH |
| Round-trip | `decode(encode(x)) == x` for a codec, parser and printer, serializer | MEDIUM |
| Algebraic | Idempotence, commutativity and similar laws | MEDIUM |

The two HIGH rows are each documented by several independent publishers. The two MEDIUM rows have
one counted corroborator beside the Hypothesis team's own list, so treat them as common practice
rather than as an equally sourced catalog.

## Properties Alongside Example Tests

**Tentative (MEDIUM).** On LLM-generated code, property-based and example-based tests caught
different defects, and combining them detected more than either alone. The direct measurement
covers 16 problems (Tanaka et al.); a second study's full text was not reached (Holloway et al.).

**Editorial synthesis.** Beck's examples drive the TDD cycle one small step at a time
([methodology-beck.md](methodology-beck.md)); a property does not replace that step, it widens the
inputs a finished behavior is checked against. Khorikov's four pillars still grade the result
([four-pillars-khorikov.md](four-pillars-khorikov.md)): a property is a test like any other, and an
always-true or type-only property has no protection against regressions however many cases it runs.

## Properties an Agent Writes

| Study | Population and model | What it found |
|---|---|---|
| Maaz, DeVoe, Hatfield-Dodds, Carlini (NeurIPS 2025 DL4Code workshop paper) | A Claude Code-based agent (Claude Opus 4.1, per the paper's HTML) writing Hypothesis tests over 100 popular, mature, human-written Python packages | 56% of a 50-report sample were valid bugs, 18 of 21 top-ranked reports were valid, 3 patches merged. The agent cannot tell intentional design from a bug; the invalid share mixes wrong properties with legitimate but unwanted edge cases |
| Vikram, Lemieux, Sunshine, Padhye (2024) | GPT-4, Gemini-1.5-Pro and Claude 3 Opus generating properties from API docs for 40 Python library methods | Generated properties were often invalid or unsound; the best setup needed several samples on average for a valid and sound one, and mutation-based property coverage stayed low |
| PROBE: Li, Liu, Zhang, Gao, Sun (ACL 2026 Findings) | LLM-written property-based tests | A "superficiality gap": properties a wrong implementation also satisfies. Generating counter-implementations to expose them raised the mutation score |

Taken together (HIGH across the three pools, on Python libraries and benchmark functions, not on
agent-written code under development): agents can write properties that find real bugs, and a
material share of the properties they write are unsound or superficial. So a property needs
evidence that it **can fail**: a mutant it kills, a counter-implementation it rejects, or a
known-bad input marked expected-fail (Hypothesis documents `@example(...).xfail()` for this).

No 2025-2026 source found evaluates a property author that never sees the code. Building one is a
design choice to measure, not an evidence-backed default.

## Where the Practice Lives

- Writing a property test in the project: `/testing:write`.
- Whether a property's expected side is independent enough to keep: `/testing:test-value`.
- Showing a property can fail, with mutants: `/mutation-testing:audit`; why mutants grade
  properties: `/mutation-testing:principles`.

When those plugins are not enabled, the rule of thumb is this file's: state the property from
intent, pin the shrunk input as an explicit example, and show the property can fail before trusting
a green run.

## Sources

Read on 2026-10-06, at the depth noted. Recheck trigger: a Hypothesis or fast-check major release
changes the explicit-example or database semantics, or a revised version of Maaz et al. or PROBE
changes the figures above.

- Hypothesis API reference, tutorial on replaying failures, and changelog
  (<https://hypothesis.readthedocs.io/en/latest/reference/api.html>,
  <https://hypothesis.readthedocs.io/en/latest/tutorial/replaying-failures.html>,
  <https://hypothesis.readthedocs.io/en/latest/changelog.html>). Docs read.
- fast-check: reading test reports and user-definable values
  (<https://fast-check.dev/docs/tutorials/quick-start/read-test-reports/>,
  <https://fast-check.dev/docs/configuration/user-definable-values/>), model-based testing
  (<https://fast-check.dev/docs/advanced/model-based-testing/>). Docs read.
- rapid (<https://pkg.go.dev/pgregory.net/rapid>), CsCheck (<https://github.com/AnthonyLloyd/CsCheck>),
  FsCheck (<https://fscheck.github.io/FsCheck/RunningTests.html>), QuickCheck 2.19
  (<https://hackage-content.haskell.org/package/QuickCheck-2.19.0.0/docs/Test-QuickCheck.html>).
  Docs read.
- HypothesisWorks `/hypothesis` Claude Code command
  (<https://raw.githubusercontent.com/HypothesisWorks/hypothesis/master/.claude/commands/hypothesis.md>),
  fetched from master; it may have changed since its 2025-11-01 announcement.
- Kiro correctness docs (<https://kiro.dev/docs/specs/correctness/>). Docs read.
- Scott Wlaschin, property categories (2014,
  <https://fsharpforfunandprofit.com/posts/property-based-testing-2/>); Chen et al., metamorphic
  testing survey (ACM CSUR 2018, <https://i.cs.hku.hk/~tse/Papers/2010s/hlmtCSUR.html>).
- Maaz et al. (<https://arxiv.org/abs/2510.09907>). Abstract and HTML read.
- Vikram et al. (<https://arxiv.org/abs/2307.04346>). Abstract read.
- PROBE (<https://aclanthology.org/2026.findings-acl.683/>). Conference page read, full text not.
- Tanaka et al. (<https://arxiv.org/abs/2510.25297>), abstract read; Holloway et al.
  (<https://icml.cc/virtual/2026/77983>), conference page read, full text not reached.
