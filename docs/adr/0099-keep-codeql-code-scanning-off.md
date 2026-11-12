# Keep CodeQL code scanning off

- Status: accepted
- Date: 2026-11-12
- Refs: owner decision of 2026-11-12, following owner decision Q29

## Context

The owner approved CodeQL default setup (Q29). It was turned on at 2026-11-12 00:28Z for
`actions`, `javascript-typescript` and `python` with the default query suite, and the
address-feedback lane was taught to work CodeQL review threads
([#15474](https://github.com/melodic-software/claude-code-plugins/pull/15474), merged as
[4800f440](https://github.com/melodic-software/claude-code-plugins/commit/4800f440e8f050114b35f36e77a97a77a19a2b57)).

Default setup scans on each push to the default or a protected branch, on every pull request
against them, and weekly
([About setup types for code scanning](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types)).
It is not a weekly-only scan.

Measured between 00:28Z and 02:53Z on 2026-11-12:

- Each pull request run had 3 jobs, took 4:46 to 5:07 wall time and about 7 job-minutes. Standard
  GitHub-hosted runners in public repositories are listed as free
  ([GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)).
- Each run on `main` took 19 job-minutes; the JavaScript/TypeScript job alone took 14:26.
- Volume was about 35 runs and 105 jobs an hour.
- Each Analyze job makes an estimated 11 to 19 REST core calls: feature flags, repository
  properties, status-report PUTs, the SARIF upload and its processing polls, with a rate-limited
  403 retried up to 4 times. This is a source-based estimate from
  [github/codeql-action at 33d7b85](https://github.com/github/codeql-action/tree/33d7b85da1a04171e211befe2c739303b9a4c066),
  not a measurement. It comes to 33 to 57 calls per pull request and, at 105 jobs an hour, about
  1,150 to 2,000 an hour: 23 to 40 percent of the 5,000-an-hour `GITHUB_TOKEN` installation pool
  that the review lanes and `ci-status` share.

While CodeQL was on, that pool ran out at 00:46Z, about 01:53Z and 02:39Z, and CodeQL's own upload
step failed with "API rate limit exceeded for installation" on 7 pull request runs. The agreed
rollback condition fired, and default setup was set to not configured at about 02:53Z.

The owner's rule is that nothing may reduce throughput. Two controls already cover the same risk:
the security-review lane on every ready pull request
(`.github/workflows/pr-review-security-hosted.yml`), and zizmor on workflow changes (the
`Run zizmor` step in `.github/workflows/pr-require-checks.yml`). The first scan's 2 critical
alerts (untrusted checkout) were false positives.

## Decision

1. CodeQL code scanning stays off for this repository: default setup stays not configured, and no
   advanced-setup workflow is added.

Rejected: default setup on, for its load on every pull request and every protected-branch push
against the shared installation pool.

Deferred: a schedule-only advanced-setup workflow run weekly off-peak, at about 60 calls a week.
It waits for the hardening phase (Revisit triggers).

## Consequences

- The 206 alerts from the one scan are triaged to zero separately: real ones fixed, false
  positives dismissed.
- Nothing re-scans until this record is revisited, so new code gets no CodeQL analysis; the
  security-review lane and zizmor remain the code and workflow security checks.
- The address-feedback support for CodeQL threads stays in place and is idle while scanning is
  off.

## Revisit triggers

- Open issues and open pull requests reach zero and the hardening phase begins: reconsider the
  deferred weekly workflow first.
- GitHub moves code-scanning API calls off the installation `GITHUB_TOKEN` pool.
