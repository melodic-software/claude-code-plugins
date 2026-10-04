# Property-based tests

Load this file when a test should hold for a whole range of inputs instead of for the few values a
person picks. The library builds hundreds of inputs, checks a rule against each, and on a failure
reduces the input to a small one that still breaks the rule. The cadence in [write.md](write.md)
still applies: write one property, watch it fail for the right reason, make it pass, refactor.

## Find the rule first

Ask these questions about the code under test, in this order. The first "yes" gives the property.

1. **Is anything conserved?** Splitting a bill must hand out exactly the total; partitioning a list
   must keep every element exactly once; a ledger transfer leaves the sum of balances unchanged.
2. **Is there a reverse operation?** Formatting a duration as `1h30m` and parsing it back yields
   the same duration; a serializer and its deserializer, or a parser and a printer, pair the same
   way.
3. **Does a second pass change anything?** Trimming whitespace, canonicalizing a path, or
   collapsing duplicate tags a second time must leave the first result as it was.
4. **Can the output be checked cheaply?** A scheduler's output has no overlapping slots; a
   paginator returns pages no longer than the page size whose lengths add up to the item count; a
   top-k function returns k items, each at least as large as anything it left out.
5. **Do argument order or grouping matter?** Merging two sets of permissions gives the same result
   whichever comes first; combining three configs gives the same result however they are grouped.
6. **Is there a slower version you trust?** A new index lookup must agree with a scan of the whole
   list; a rewritten pricing rule must agree with the legacy rule it replaces.

When every answer is "no", write example tests. A property that only proves the function returned
without an exception adds almost nothing over one example.

Keep some example tests alongside the properties, in a file of their own (see the audit section
below for why). A reader learns the behavior from a worked case
with a literal answer (`format(5400s) == "1h30m"`), and requirement boundaries deserve a named test
of their own.

## The oracle never reruns the code

The assertion has to be able to fail when the implementation is wrong. Rebuilding the expected value
with the same computation does not qualify: `assert split(total, n) == [total / n] * n` agrees with
`split` whenever both make the same rounding mistake. `/testing:test-value` sets the rule for every
expected value (it needs a source outside the code under test) and names a property as a level that
can supply one. The rule above is what makes that true.

For the bill example the oracle is three checks, none of which divides the total:

- the shares sum to the total, to the cent;
- there are exactly `n` shares;
- the largest and smallest share differ by at most one cent.

A trusted slower version (question 6) is a valid oracle only when it was written separately and is
simpler than the code. A copy of the implementation used as the reference repeats every bug in it.

## Writing generators

- **Describe the accepted input and generate exactly that.** For an invoice of 1 to 50 lines that
  share one currency, draw the currency once and pass it to the line generator. Rejecting generated
  values after the fact means many runs test nothing, and the reported case count overstates the
  coverage.
- **Compose.** Build an invoice generator from line, amount and currency generators so each piece is
  reused and constrained in one place.
- **Seed known trouble.** Add any input that broke the code before, and any value a requirement
  names, as a fixed example the library runs every time.
- **Size the run per environment.** Use a small case count while editing and a larger one in CI. If
  the library fails a case for running too long and the code is slow by design, lift that limit so
  hardware speed does not decide the result.

## When a property fails

1. Replay it. Record the seed or rely on the library's saved failures, so the same input reruns
   locally and in CI.
2. Read the reduced input and check it against what the function documents it accepts.
3. If a caller could legally send it, the code has a defect: fix it and keep the reduced input as an
   example test, so the regression stays covered even if the generator never produces that value
   again.
4. If no caller could send it, narrow the generator to the documented input. If the rule itself
   promised more than the requirement does, restate it. Loosening an assertion only to get green is
   not a fix.

## How this matches `/testing:audit`

The audit's `rule-recomputed-derived` rule reports expected values built from the call's own
arguments. Each language adapter under the audit skill's `adapters/` directory lists the property
markers it recognizes (`property_markers`), and the audit does not apply this rule to any file that contains one of them,
because a property computes its expectation
from generated inputs by design. The skip applies to the whole file, which has two effects:

- Nothing automated catches a property whose oracle reruns the algorithm; the author and the
  reviewer check the oracle against the rule above.
- An example test placed in the same file as a property is skipped too. Put example tests in their
  own file so the audit still checks their expected values.

## Language references

Work out the language of the code under test from its manifests and source files, then read only
the matching reference:

| Code under test | Reference |
|---|---|
| Python (`pyproject.toml`, `setup.cfg`, `requirements*.txt`, `.py` sources) | [property-based/python.md](property-based/python.md) |
| TypeScript or JavaScript (`package.json`, `.ts` or `.js` sources) | [property-based/typescript.md](property-based/typescript.md) |
| C# (`.csproj`, `.sln`, `.cs` sources) | [property-based/csharp.md](property-based/csharp.md) |

In any other language read none of them; apply this page with whatever property library the project
already uses. If the project has none, ask the user before introducing a library, and cover the rule
with example tests until they agree.
