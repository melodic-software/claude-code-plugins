# Mixed Reference

This file has a basically mixed shape — some really tight directives, some quite verbose filler. Used as fixture for batch-mode compression evals.

## Hard rules

- **Tier 0 outranks Tier 3.** Non-negotiable.
- **Verify CLI flags via `<bin> --help` this turn.** Training-recall is Tier 3 and MUST be promoted.

## Some Additional Context

So basically, the point of this section is just to add some kind of verbose prose into the mix. You'll notice that it's really not all that disciplined — there's quite a lot of hedging and filler that could pretty easily be cut.

## Output schema

```text
<file>: <action> (pct=N.N%, lint=PASS|FAIL)
```

`action` ∈ {`compressed`, `reverted`, `skipped`}.
