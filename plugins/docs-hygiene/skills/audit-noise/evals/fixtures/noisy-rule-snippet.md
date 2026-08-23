# Retry policy

## Why this file exists

This file exists to document the retry policy. It was created because we kept
re-litigating retry behavior in review, so we wrote it down here to settle it.

Path-scoped to `src/net/**`; loads on Read of any file under that tree.

## Policy

Empirically observed 2026-03-14: three retries with exponential backoff clears the
transient socket resets we saw in the incident. Cap total wait at 30s.

For per-slice overrides, see `.work/net-hardening-slice/PLAN.md` for the worked
example the author drafted.

The following three skills consume this rule: `/net-audit`, `/net-lint`, `/net-verify`.

As you asked, the cap sits at 30s rather than the 45s default.

Task 2 replaces the old fixed-delay retry, and in this PR we make backoff the default.

See PR #45 for the ordering rationale.

## Cross-references

- `src/net/backoff.md` — backoff curve derivation
