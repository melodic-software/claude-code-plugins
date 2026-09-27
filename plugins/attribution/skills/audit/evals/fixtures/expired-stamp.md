# Widget Runner notes

Internal notes on how this repository drives Widget Runner, a fictional build tool used only as
an eval fixture. Nothing here describes a real product.

## Retry behavior

The runner accepts three retry strategies: `none`, `linear`, and `exponential`. We use `linear`
because our failures cluster rather than spread, and exponential backoff would idle the agents.

**Verification record.** Claim: the runner's `retry` key accepts exactly those three values.
Basis: `https://example.invalid/widget-runner/docs/retry`. Verified 2024-03-04. Recheck trigger:
the runner's major version changes.

## Cache directory

The cache lives under the workspace root by default. Overriding it is a per-project decision and
we have not needed to.
