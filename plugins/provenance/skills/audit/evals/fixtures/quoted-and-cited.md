# Widget Runner concurrency, quoted

A hard-negative fixture: the external material here is quoted and attributed, so it must NOT
become a finding. Widget Runner is fictional and exists only for this fixture.

The upstream documentation is explicit about the default:

> Widget Runner executes one job per core by default, and refuses to oversubscribe unless
> `--force-parallel` is passed.
>
> — Widget Runner docs, `https://example.invalid/widget-runner/docs/concurrency`, read 2026-08-20

We accept that default. Our agents are memory-bound rather than CPU-bound, so oversubscribing
would trade a small wall-clock gain for eviction churn we have measured as worse.

The docs also note, inline, that "`--force-parallel` is unsupported on Windows"
(`https://example.invalid/widget-runner/docs/concurrency`, read 2026-08-20), which is why our
Windows lane never sets it.
