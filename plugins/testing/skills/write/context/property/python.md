# Property-based tests in Python: Hypothesis

This page maps [../property.md](../property.md) onto Hypothesis. If the project uses a
different property library, apply the same page with that library's docs.

- **Declaring a property.** Decorate the test with `@given(...)` and give it one strategy per
  parameter. The audit's pytest adapter treats that decorator as its property marker and skips
  `rule-recomputed-derived` for that test only; an example test in the same module is still checked.
- **Constraining inputs.** Strategy arguments carry the input rules:
  `st.integers(0, 10_000_000)` for an amount in cents, `st.text(min_size=1, max_size=40)` for a
  name. For a value that depends on another (the invoice currency shared by every line), write an
  `@st.composite` strategy or chain with `.flatmap`. `assume()` and `.filter()` throw values away
  after generation; use them only when no strategy argument says the same thing.
- **Fixed inputs.** Each `@example(...)` decorator adds one input that Hypothesis runs before any
  generated ones, which is where a past bug's input belongs.
- **Run size.** `@settings(...)` sets `max_examples` and the per-case `deadline` for one test; a
  registered settings profile, chosen per environment, sets them for the suite. Pass
  `deadline=None` for code that is slow by design.
- **Saved failures.** Hypothesis writes failing inputs to its example database and retries them on
  the next run. Do not commit that directory unless the team shares it deliberately, and copy the
  reduced input into an `@example` or a plain test when you fix the bug.

Pointers: [`@given`](https://hypothesis.readthedocs.io/en/latest/reference/api.html#hypothesis.given),
[`@example`](https://hypothesis.readthedocs.io/en/latest/reference/api.html#hypothesis.example),
[`@settings`](https://hypothesis.readthedocs.io/en/latest/reference/api.html#hypothesis.settings)
and the [example database](https://hypothesis.readthedocs.io/en/latest/reference/api.html#hypothesis.database.DirectoryBasedExampleDatabase).
