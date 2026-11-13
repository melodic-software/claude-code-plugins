# Review instructions

Managed Code Review gives every review agent this file's contents as the
repository's review instructions. Its citations, the
`standards/review/<file>.md#<heading>` paths in parentheses, are not include
lines, so Managed Code Review does not read the cited files and sees only the
words printed below (see "Depth"). A self-hosted or local review running the
`review` plugin also follows each citation into the `standards` repository
for the full criterion behind the line.

Review in this organization splits into two mutually exclusive scopes, so a
finding belongs to exactly one and is never reported twice. The **code-review lane**
(`pr-review`, and Managed Code Review) reads this file and applies the
code-review scope below. The **security lane** (`pr-review-security`) runs
from its own security-only prompt, not this file; the security scope below
records the split for every surface that does read this file, so the
code-review lane knows what to leave to the security lane, and a self-hosted
or local review (for example a `review`-plugin security agent) applies the
right section.

## Severity

This organization's criteria (`standards/review/` in `standards`) resolve
to three severities: **Critical**, **Important**, **Suggestion**. On this
surface's three markers:

| SSOT severity | Managed marker |
| --- | --- |
| Critical | 🔴 Important |
| Important | 🔴 Important |
| Suggestion | 🟡 Nit |

🟣 Pre-existing is not an SSOT severity: it is this surface's own <!-- ai-slop-ignore: severity-marker vocabulary, load-bearing -->
detection-time judgment of whether a finding predates the diff, orthogonal
to the three severities above, and no criterion assigns it.

A finding tagged `blocking` is always 🔴 Important here, whatever severity its
criterion would otherwise carry in context. `blocking` is this file's own
tag, not a severity a `standards/review/` criterion assigns.

## Depth

Managed Code Review does not follow a citation below: a citation is not an
include line
([Include other files in REVIEW.md](https://code.claude.com/docs/en/code-review-customize#include-other-files-in-review-md)),
so the cited file never reaches the review. A self-hosted or local review
using the `review` plugin follows one into the full criterion, its severity
nuance, and its sources, resolving the path from the `standards` checkout
root: this repository's own root when `standards` reviews itself, or the
`--add-dir` mount root everywhere else.

A reviewed repository's `docs/review/README.md`, when present, indexes its
own per-concern review criteria, and a self-hosted or local review also
reads the files there whose concern the change touches. Those paths resolve against
the reviewed repository's root, not the `standards` checkout or its
`--add-dir` mount.

## Code-review lane scope

This lane owns every review dimension except security: correctness,
design, conventions, error handling, observability, tests, and
documentation. On a repository whose CI runs the security lane (a
`.github/workflows/pr-review-security*.yml` workflow exists), it does
**not** report security findings, such as vulnerabilities, authorization
or tenancy gaps, credential exposure, or injection: each belongs to that
lane alone and is omitted here even when a hunk plainly contains one.
On a repository with no such workflow, no other lane would report them:
report security findings here too, applying the security-scope checks below.

Always check:

- A high-risk security action, such as authentication, an authorization
  failure, a privilege change, or sensitive-data access, has a matching
  audit-log entry (`standards/review/observability.md#logging`). This checks
  logging completeness; whether the action itself is safe is the security
  lane's question.
- A change that writes two or more related records, files, or state
  locations carries an atomicity mechanism spanning them: a transaction,
  an atomic rename, a constraint, or a compensation step. An
  interruption between steps must not leave state no code path expects
  (`standards/review/error-handling.md#atomicity`).
- No Dependabot pull request waits on a human. One whose updates are all
  non-major, with GitHub Actions only from `actions/*`, `github/*` or
  `anthropics/*`, and none in the policy's `reviewOnly` security-critical
  list, merges once `ci-status` passes. Any other, a major included, merges
  on an AI review lane's `merge` verdict at its current head once
  `ci-status` passes, and a verdict on a security-critical dependency cites
  the threat-model control it checked. A change that adds an action from
  another publisher says why no vendor action or `gh` or script step serves
  (`components/dependabot-policy/README.md#merge-tiers-for-dependabot-pull-requests`).

## Security lane scope

This lane reports **only** security findings: vulnerabilities, missing
authorization or tenant scoping, exposed secrets or credentials, injection,
and their direct enablers. Everything else, including style, design,
correctness with no security impact, and test coverage, belongs to the
code-review lane; omit it.

Always check:

- A handler or endpoint that receives an object id (a path segment, body
  field, or query parameter) checks the caller is authorized for that
  specific record, not only that the id is well-formed. Tagged `blocking`
  (`standards/review/security.md#object-level-authorization`).
- A data-access path that reaches tenant-owned data carries an explicit
  tenant scope. Tagged `blocking`
  (`standards/review/multi-tenancy.md#tenant-scoped-data-access`).
- No secret, token, or credential is added to tracked source or config.
  Tagged `blocking` (`standards/review/security.md#secrets-and-credentials`).
- A query or process invocation built from external input is parameterized,
  never string-concatenated. Tagged `blocking`
  (`standards/review/security.md#trust-boundaries-and-injection`).
